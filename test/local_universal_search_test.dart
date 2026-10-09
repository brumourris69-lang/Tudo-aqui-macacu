import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/pages/universal_search_page.dart';
import 'package:tudo_aqui_macacu/features/search/models/search_result.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/universal_search_repository.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/local_universal_search_repository.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';

const result = SearchResult(
  id: 'local-eletronica-vieira',
  sourceCollection: 'establishments',
  title: 'Eletrônica Vieira',
  summary: 'Fictício',
  category: 'Tecnologia',
  subcategory: 'Eletrônicos',
  type: SearchResultType.establishment,
  destination: SearchDestination.businessProfile,
);

class FakeSearch implements UniversalSearchRepository {
  final requests = <BusinessSearchRequest>[];
  final pending = <Completer<BusinessSearchPage>>[];
  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) {
    requests.add(request);
    final completer = Completer<BusinessSearchPage>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  test(
    'transport preserves ID, excludes private fields and external image',
    () {
      final raw = {
        ...result.toMap(),
        'privateNotes': 'secret',
        'imageUrl': 'https://outside.invalid/photo',
      };
      final page = decodeLocalSearchPage({
        'results': [raw],
        'nextCursor': null,
      }, BusinessSearchRequest(query: 'ele'));
      expect(page.results.single.id, result.id);
      expect(page.results.single.imageUrl, '');
      expect(page.results.single.toMap().containsKey('privateNotes'), false);
    },
  );
  test(
    'transport rejects foreign collection, cursor and oversized response',
    () {
      final request = BusinessSearchRequest(query: 'ele', limit: 1);
      for (final body in [
        {
          'results': [
            {...result.toMap(), 'sourceCollection': 'users'},
          ],
        },
        {
          'results': [result.toMap()],
          'nextCursor': {
            'queryKey': 'wrong',
            'lastIndexId': 'establishments__id',
          },
        },
        {
          'results': [result.toMap(), result.toMap()],
        },
      ]) {
        expect(
          () => decodeLocalSearchPage(body, request),
          throwsFormatException,
        );
      }
    },
  );
  testWidgets('two character minimum, debounce, stale response and clear', (
    tester,
  ) async {
    final repo = FakeSearch();
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repo)),
    );
    await tester.enterText(find.byType(TextField), 'e');
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.requests, isEmpty);
    await tester.enterText(find.byType(TextField), 'el');
    await tester.pump(const Duration(milliseconds: 349));
    expect(repo.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'pad');
    await tester.pump(const Duration(milliseconds: 350));
    repo.pending[0].complete(BusinessSearchPage([result], null));
    await tester.pump();
    expect(find.text(result.title), findsNothing);
    repo.pending[1].complete(BusinessSearchPage([], null));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum resultado encontrado.'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpar pesquisa'));
    await tester.pumpAndSettle();
    expect(find.text('Digite pelo menos dois caracteres.'), findsOneWidget);
  });
  testWidgets('filters, pagination and unavailable filters', (tester) async {
    final repo = FakeSearch();
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repo)),
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'Turismo · em breve'),
          )
          .onSelected,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'modelo');
    await tester.pump(const Duration(milliseconds: 350));
    final cursor = BusinessSearchCursor(
      repo.requests[0].queryKey,
      'establishments__test',
    );
    repo.pending[0].complete(BusinessSearchPage([result], cursor));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carregar mais'));
    await tester.pump();
    expect(repo.requests.last.cursor, cursor);
    repo.pending[1].complete(BusinessSearchPage([result], null));
    await tester.pumpAndSettle();
    expect(find.text(result.title), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Serviços'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(repo.requests.last.filter, BusinessSearchFilter.services);
    repo.pending.last.complete(BusinessSearchPage([], null));
    await tester.pumpAndSettle();
  });
  testWidgets('safe connection error and retry', (tester) async {
    final repo = FakeSearch();
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repo)),
    );
    await tester.enterText(find.byType(TextField), 'el');
    await tester.pump(const Duration(milliseconds: 350));
    repo.pending[0].completeError(StateError('private error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verifique a conexão local'), findsOneWidget);
    expect(find.textContaining('private error'), findsNothing);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    repo.pending[1].complete(BusinessSearchPage([result], null));
    await tester.pumpAndSettle();
    expect(find.text(result.title), findsOneWidget);
  });
  testWidgets('original ID resolves existing profile, favorites preserved', (
    tester,
  ) async {
    final repo = FakeSearch();
    final saved = <String>{};
    String? resolved;
    final business = Business(
      'Eletrônica Vieira',
      'Tecnologia',
      'Eletrônicos',
      'Fictício',
      'Local',
      0,
      id: result.id,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UniversalSearchPage(
          repository: repo,
          saved: saved,
          onFavorite: (value) => saved.add(value.favoriteKey),
          resolveBusiness: (id) async {
            resolved = id;
            return business;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'ele');
    await tester.pump(const Duration(milliseconds: 350));
    repo.pending[0].complete(BusinessSearchPage([result], null));
    await tester.pumpAndSettle();
    await tester.tap(find.text(result.title));
    await tester.pumpAndSettle();
    expect(resolved, result.id);
    expect(find.byType(BusinessProfile), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(saved, contains(result.id));
  });
  testWidgets('unavailable original does not open profile', (tester) async {
    final repo = FakeSearch();
    await tester.pumpWidget(
      MaterialApp(
        home: UniversalSearchPage(
          repository: repo,
          resolveBusiness: (_) async => null,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'ele');
    await tester.pump(const Duration(milliseconds: 350));
    repo.pending[0].complete(BusinessSearchPage([result], null));
    await tester.pumpAndSettle();
    await tester.tap(find.text(result.title));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessProfile), findsNothing);
    expect(
      find.text('Este estabelecimento não está disponível.'),
      findsOneWidget,
    );
  });
}
