import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/search/models/search_result.dart';
import 'package:tudo_aqui_macacu/features/search/pages/universal_search_page.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/universal_search_repository.dart';

class SearchRepository implements UniversalSearchRepository {
  SearchRepository(this.result);
  final SearchResult result;
  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) async =>
      BusinessSearchPage([result], null);
}

class RetrySearchRepository implements UniversalSearchRepository {
  var calls = 0;

  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) async {
    calls++;
    if (calls == 1) throw Exception('private transport detail');
    return BusinessSearchPage([publicResult], null);
  }
}

class PaginatedSearchRepository implements UniversalSearchRepository {
  PaginatedSearchRepository(this.pages);

  final List<BusinessSearchPage> pages;
  final requests = <BusinessSearchRequest>[];

  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) async {
    requests.add(request);
    return pages[requests.length - 1];
  }
}

const publicResult = SearchResult(
  id: 'pilot-livraria-exemplo',
  sourceCollection: 'establishments',
  title: 'Livraria Piloto',
  summary: 'Resumo fictício',
  category: 'Comércio',
  subcategory: 'Livraria',
  type: SearchResultType.establishment,
  destination: SearchDestination.businessProfile,
);

const secondPublicResult = SearchResult(
  id: 'pilot-cafe-exemplo',
  sourceCollection: 'establishments',
  title: 'Café Piloto',
  summary: 'Outro resumo público',
  category: 'Onde comer?',
  subcategory: 'Cafeteria',
  type: SearchResultType.establishment,
  destination: SearchDestination.businessProfile,
);

Widget app({Set<BusinessSearchFilter>? supportedFilters}) => MaterialApp(
  home: UniversalSearchPage(
    repository: SearchRepository(publicResult),
    supportedFilters: supportedFilters,
  ),
);

void main() {
  testWidgets('pilot displays only the supported establishment filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        supportedFilters: {
          BusinessSearchFilter.all,
          BusinessSearchFilter.commerce,
          BusinessSearchFilter.services,
        },
      ),
    );

    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Comércios'), findsOneWidget);
    expect(find.text('Serviços'), findsOneWidget);
    expect(find.text('Turismo'), findsNothing);
    expect(find.text('Empregos'), findsNothing);
    expect(find.text('Eventos'), findsNothing);
    expect(find.text('Notícias'), findsNothing);
    expect(find.text('Utilidades'), findsNothing);
  });

  testWidgets('default search page retains the existing filter catalog', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    for (final label in [
      'Todos',
      'Comércios',
      'Serviços',
      'Turismo',
      'Empregos',
      'Eventos',
      'Notícias',
      'Utilidades · em breve',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('recoverable error offers retry and updates to search results', (
    tester,
  ) async {
    final repository = RetrySearchRepository();
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repository)),
    );

    await tester.enterText(find.byType(TextField), 'livraria');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(find.text('Não foi possível pesquisar.'), findsOneWidget);
    expect(find.text('private transport detail'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('Não foi possível pesquisar.'), findsNothing);
    expect(find.text('Livraria Piloto'), findsOneWidget);
  });

  testWidgets('load more sends the next cursor and appends unique results', (
    tester,
  ) async {
    const nextCursor = BusinessSearchCursor(
      'all:livraria',
      'establishments__pilot-livraria-exemplo',
    );
    final repository = PaginatedSearchRepository([
      BusinessSearchPage([publicResult], nextCursor),
      BusinessSearchPage([publicResult, secondPublicResult], null),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repository)),
    );

    await tester.enterText(find.byType(TextField), 'livraria');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.cursor, isNull);
    expect(find.text('Carregar mais'), findsOneWidget);
    expect(find.text('Livraria Piloto'), findsOneWidget);

    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(2));
    expect(repository.requests[1].cursor?.queryKey, 'all:livraria');
    expect(
      repository.requests[1].cursor?.lastIndexId,
      'establishments__pilot-livraria-exemplo',
    );
    expect(find.text('Livraria Piloto'), findsOneWidget);
    expect(find.text('Café Piloto'), findsOneWidget);
    expect(find.text('2 carregados'), findsOneWidget);
    expect(find.text('Carregar mais'), findsNothing);
  });

  testWidgets('empty search results show empty state without another page', (
    tester,
  ) async {
    final repository = PaginatedSearchRepository([
      BusinessSearchPage(const [], null),
    ]);
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repository)),
    );

    await tester.enterText(find.byType(TextField), 'inexistente');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(1));
    expect(find.text('Nenhum resultado encontrado.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Carregar mais'), findsNothing);
  });

  testWidgets(
    'establishment details use the injected resolver and original ID',
    (tester) async {
      String? resolvedId;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchPage(
            repository: SearchRepository(publicResult),
            supportedFilters: const {
              BusinessSearchFilter.all,
              BusinessSearchFilter.commerce,
              BusinessSearchFilter.services,
            },
            resolveBusiness: (id) async {
              resolvedId = id;
              return Business.fromData(id, {
                'name': 'Livraria Piloto',
                'category': 'Comércio',
                'subcategory': 'Livraria',
                'shortDescription': 'Resumo fictício',
                'location': '',
              });
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'livraria');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Livraria Piloto').last);
      await tester.pumpAndSettle();

      expect(resolvedId, 'pilot-livraria-exemplo');
      expect(find.text('Resumo fictício'), findsWidgets);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.text('Ligação'), findsNothing);
      expect(find.text('Instagram'), findsNothing);
      expect(find.text('Como chegar'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Resultados encontrados'), findsOneWidget);
      expect(find.text('Livraria Piloto'), findsOneWidget);
    },
  );

  testWidgets('pilot detail sharing does not touch Firebase telemetry', (
    tester,
  ) async {
    expect(Firebase.apps, isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: UniversalSearchPage(
          repository: SearchRepository(publicResult),
          supportedFilters: const {
            BusinessSearchFilter.all,
            BusinessSearchFilter.commerce,
            BusinessSearchFilter.services,
          },
          trackBusinessShareMetrics: false,
          resolveBusiness: (id) async => Business.fromData(id, {
            'name': 'Livraria Piloto',
            'category': 'Comércio',
            'subcategory': 'Livraria',
            'shortDescription': 'Resumo fictício',
            'location': '',
          }),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'livraria');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Livraria Piloto').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Compartilhar'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Compartilhar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(Firebase.apps, isEmpty);
  });
}
