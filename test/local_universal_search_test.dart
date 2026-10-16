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
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/features/news/models/public_news_article.dart';
import 'package:tudo_aqui_macacu/features/news/pages/news_article_page.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/pages/event_detail_page.dart';
import 'package:tudo_aqui_macacu/features/jobs/models/public_job.dart';
import 'package:tudo_aqui_macacu/features/jobs/pages/job_detail_page.dart';

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
const tourismResult = SearchResult(
  id: 'route-original-id',
  sourceCollection: 'routes',
  title: 'Cachoeira Macacu',
  summary: 'Trilhas em Bacia do Rio Macacu',
  category: 'Cachoeiras',
  subcategory: '',
  type: SearchResultType.tourism,
  destination: SearchDestination.touristSpotDetail,
);
const newsResult = SearchResult(
  id: 'news-original-id',
  sourceCollection: 'news',
  title: 'Notícia Macacu',
  summary: 'Atualização fictícia',
  category: 'Cidade',
  subcategory: '',
  type: SearchResultType.news,
  destination: SearchDestination.newsArticle,
);
const eventResult = SearchResult(
  id: 'event-original-id',
  sourceCollection: 'events',
  title: 'Festival Fictício',
  summary: 'Evento de teste',
  category: 'Cultura',
  subcategory: '',
  type: SearchResultType.events,
  destination: SearchDestination.eventDetail,
  eventDate: '25/10/2026 às 19h',
  location: 'Praça de Teste',
);
const jobResult = SearchResult(
  id: 'job-original-id',
  sourceCollection: 'jobs',
  title: 'Auxiliar Administrativo',
  summary: 'Vaga fictícia de teste',
  category: 'Administrativo',
  subcategory: '',
  type: SearchResultType.jobs,
  destination: SearchDestination.jobDetail,
  company: 'Empresa Exemplo',
  location: 'Centro',
  employmentType: 'CLT',
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
  testWidgets(
    'invalid queries are explained without backend call or connection retry',
    (tester) async {
      final repo = FakeSearch();
      await tester.pumpWidget(
        MaterialApp(home: UniversalSearchPage(repository: repo)),
      );
      for (final query in [
        'pão e café',
        'um dois tres quatro cinco',
        'x' * 25,
        'x' * 81,
      ]) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(repo.requests, isEmpty);
        expect(find.text('Revise os termos da pesquisa.'), findsOneWidget);
        expect(
          find.text(SearchQueryValidationException.description),
          findsOneWidget,
        );
        expect(find.textContaining('Verifique a conexão local'), findsNothing);
        expect(find.text('Tentar novamente'), findsNothing);
      }
      await tester.enterText(find.byType(TextField), 'ele');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.requests, hasLength(1));
      repo.pending.single.complete(BusinessSearchPage([], null));
      await tester.pumpAndSettle();
      expect(find.text('Revise os termos da pesquisa.'), findsNothing);
    },
  );

  testWidgets(
    'pagination preserves equal IDs in separate collections and opens event detail',
    (tester) async {
      final repo = FakeSearch();
      var resolveCalls = 0;
      final pending = SearchResult.fromMap({
        ...result.toMap(),
        'sourceCollection': 'events',
        'type': 'events',
        'destination': 'eventDetail',
        'title': 'Evento apenas em contrato',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchPage(
            repository: repo,
            resolveBusiness: (_) async {
              resolveCalls++;
              return null;
            },
            resolveEvent: (id) async {
              expect(id, pending.id);
              return null;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'ele');
      await tester.pump(const Duration(milliseconds: 350));
      final cursor = BusinessSearchCursor(
        repo.requests.single.queryKey,
        'establishments__test',
      );
      repo.pending.single.complete(BusinessSearchPage([result], cursor));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carregar mais'));
      await tester.pump();
      expect(repo.requests.last.cursor, cursor);
      repo.pending.last.complete(
        BusinessSearchPage([result, pending, pending], null),
      );
      await tester.pumpAndSettle();
      expect(find.text(result.title), findsOneWidget);
      expect(find.text(pending.title), findsOneWidget);
      expect(find.text('2 carregados'), findsOneWidget);
      await tester.tap(find.text(pending.title));
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailPage), findsOneWidget);
      expect(
        find.text('Este evento não está mais disponível.'),
        findsOneWidget,
      );
      expect(resolveCalls, 0);
      expect(find.byType(BusinessProfile), findsNothing);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(result.title));
      await tester.pumpAndSettle();
      expect(resolveCalls, 1);
      expect(
        find.text('Este estabelecimento não está disponível.'),
        findsOneWidget,
      );
    },
  );
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
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Turismo'))
          .onSelected,
      isNotNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Eventos'))
          .onSelected,
      isNotNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Notícias'))
          .onSelected,
      isNotNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Empregos'))
          .onSelected,
      isNotNull,
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
    await tester.ensureVisible(find.text('Notícias'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Notícias'));
    await tester.enterText(find.byType(TextField), 'noticia');
    await tester.pump(const Duration(milliseconds: 350));
    expect(repo.requests.last.filter, BusinessSearchFilter.news);
    repo.pending.last.complete(BusinessSearchPage([newsResult], null));
    await tester.pumpAndSettle();
    await tester.tap(find.text(newsResult.title));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessProfile), findsNothing);
    await tester.ensureVisible(find.text('Eventos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Eventos'));
    await tester.enterText(find.byType(TextField), 'festival');
    await tester.pump(const Duration(milliseconds: 350));
    expect(repo.requests.last.filter, BusinessSearchFilter.events);
    repo.pending.last.complete(BusinessSearchPage([eventResult], null));
    await tester.pumpAndSettle();
    expect(find.text(eventResult.title), findsOneWidget);
    expect(find.textContaining(eventResult.eventDate), findsOneWidget);
    expect(find.textContaining(eventResult.location), findsOneWidget);
    await tester.tap(find.text(eventResult.title));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessProfile), findsNothing);
    expect(find.byType(NewsArticlePage), findsNothing);
  });
  testWidgets('jobs filter is enabled and renders public vacancy metadata', (
    tester,
  ) async {
    final repo = FakeSearch();
    await tester.pumpWidget(
      MaterialApp(home: UniversalSearchPage(repository: repo)),
    );
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Empregos'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Empregos'));
    await tester.enterText(find.byType(TextField), 'auxiliar');
    await tester.pump(const Duration(milliseconds: 350));
    expect(repo.requests.single.filter, BusinessSearchFilter.jobs);
    repo.pending.single.complete(BusinessSearchPage([jobResult], null));
    await tester.pumpAndSettle();
    expect(find.text(jobResult.title), findsOneWidget);
    expect(find.textContaining('Empresa Exemplo'), findsOneWidget);
    expect(find.textContaining('Centro'), findsOneWidget);
    expect(find.textContaining('CLT'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Empregos'))
          .onSelected,
      isNotNull,
    );
    await tester.tap(find.text(jobResult.title));
    await tester.pumpAndSettle();
    expect(find.text(jobResult.title), findsOneWidget);
    expect(find.byType(BusinessProfile), findsNothing);
  });
  test(
    'combined transport preserves IDs and allows cursor transition to routes',
    () {
      final request = BusinessSearchRequest(query: 'cachoeira');
      final page = decodeLocalSearchPage({
        'results': [result.toMap(), tourismResult.toMap()],
        'nextCursor': {
          'queryKey': request.queryKey,
          'lastIndexId': 'routes__original',
        },
      }, request);
      expect(page.results.map((item) => item.identity).toSet(), hasLength(2));
      expect(page.nextCursor?.lastIndexId, 'routes__original');
      expect(
        () => decodeLocalSearchPage(
          {
            'results': [tourismResult.toMap()],
          },
          BusinessSearchRequest(
            query: 'cachoeira',
            filter: BusinessSearchFilter.services,
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('news transport supports news and mixed-result cursors', () {
    final request = BusinessSearchRequest(
      query: 'noticia',
      filter: BusinessSearchFilter.news,
    );
    final page = decodeLocalSearchPage({
      'results': [newsResult.toMap()],
      'nextCursor': {
        'queryKey': request.queryKey,
        'lastIndexId': 'news__news-2',
      },
    }, request);
    expect(page.results.single.type, SearchResultType.news);
    expect(page.nextCursor?.lastIndexId, 'news__news-2');
    final all = BusinessSearchRequest(query: 'noticia');
    expect(
      decodeLocalSearchPage({
        'results': [result.toMap(), tourismResult.toMap(), newsResult.toMap()],
        'nextCursor': {'queryKey': all.queryKey, 'lastIndexId': 'news__news-2'},
      }, all).results.map((item) => item.identity).toSet(),
      hasLength(3),
    );
    expect(
      () => decodeLocalSearchPage(
        {
          'results': [newsResult.toMap()],
          'nextCursor': null,
        },
        BusinessSearchRequest(
          query: 'noticia',
          filter: BusinessSearchFilter.services,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => BusinessSearchRequest(
        query: 'noticia',
        filter: BusinessSearchFilter.news,
        cursor: BusinessSearchCursor(request.queryKey, 'routes__route'),
      ),
      throwsArgumentError,
    );
  });
  testWidgets(
    'tourism filter searches and existing detail is opened after resolving ID',
    (tester) async {
      final repo = FakeSearch();
      String? resolvedId;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchPage(
            repository: repo,
            resolveTourism: (id) async {
              resolvedId = id;
              return const TouristSpot(
                id: 'route-original-id',
                title: 'Cachoeira Macacu',
                category: 'cachoeiras',
                description: 'Queda fictícia',
                location: 'Macacu',
                maps: '',
                images: [],
                additionalInfo: 'Leve água',
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Turismo'));
      await tester.enterText(find.byType(TextField), 'cachoeira');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.requests.last.filter, BusinessSearchFilter.tourism);
      repo.pending.single.complete(BusinessSearchPage([tourismResult], null));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cachoeira Macacu'));
      await tester.pumpAndSettle();
      expect(resolvedId, 'route-original-id');
      expect(find.text('Leve água'), findsOneWidget);
    },
  );
  testWidgets(
    'news result opens secure article detail and back preserves search',
    (tester) async {
      final repo = FakeSearch();
      String? resolvedId;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchPage(
            repository: repo,
            resolveNewsArticle: (id) async {
              resolvedId = id;
              return PublicNewsArticle(
                id: id,
                title: 'Notícia pública Macacu',
                description: 'Texto integral da notícia publicado.',
                category: 'Cidade',
                date: DateTime(2026, 10, 9),
              );
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Notícias'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notícias'));
      await tester.enterText(find.byType(TextField), 'noticia');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.requests.last.filter, BusinessSearchFilter.news);
      repo.pending.single.complete(BusinessSearchPage([newsResult], null));
      await tester.pumpAndSettle();
      await tester.tap(find.text(newsResult.title));
      await tester.pumpAndSettle();
      expect(resolvedId, newsResult.id);
      expect(find.byType(NewsArticlePage), findsOneWidget);
      expect(find.text('Texto integral da notícia publicado.'), findsOneWidget);
      expect(find.text('09/10/2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('noticia'), findsOneWidget);
      expect(find.text(newsResult.title), findsOneWidget);
    },
  );
  testWidgets(
    'event result opens secure detail and back preserves search and filter',
    (tester) async {
      final repo = FakeSearch();
      String? resolvedId;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchPage(
            repository: repo,
            resolveEvent: (id) async {
              resolvedId = id;
              return PublicEvent(
                id: id,
                title: 'Festival público Macacu',
                description: 'Descrição completa do evento.',
                category: 'Cultura',
                eventDate: '25/10/2026 às 19h',
                location: 'Praça de Teste',
              );
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Eventos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eventos'));
      await tester.enterText(find.byType(TextField), 'festival');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.requests.last.filter, BusinessSearchFilter.events);
      repo.pending.single.complete(BusinessSearchPage([eventResult], null));
      await tester.pumpAndSettle();
      await tester.tap(find.text(eventResult.title));
      await tester.pumpAndSettle();
      expect(resolvedId, eventResult.id);
      expect(find.byType(EventDetailPage), findsOneWidget);
      expect(find.text('Descrição completa do evento.'), findsOneWidget);
      expect(find.text('25/10/2026 às 19h'), findsOneWidget);
      expect(find.text('Praça de Teste'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('festival'), findsOneWidget);
      expect(find.text('Eventos'), findsOneWidget);
      expect(find.text(eventResult.title), findsOneWidget);
    },
  );
  testWidgets(
    'job result opens secure detail and back preserves search and filter',
    (tester) async {
      final repo = FakeSearch();
      String? resolvedId;
      await tester.pumpWidget(
        MaterialApp(
          home: UniversalSearchPage(
            repository: repo,
            resolveJob: (id) async {
              resolvedId = id;
              return PublicJob(
                id: id,
                title: 'Auxiliar administrativo',
                description: 'Descrição completa da vaga.',
                category: 'Administrativo',
                company: 'Empresa Exemplo',
                location: 'Centro',
                employmentType: 'CLT',
              );
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Empregos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empregos'));
      await tester.enterText(find.byType(TextField), 'auxiliar');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.requests.last.filter, BusinessSearchFilter.jobs);
      repo.pending.single.complete(BusinessSearchPage([jobResult], null));
      await tester.pumpAndSettle();
      await tester.tap(find.text(jobResult.title));
      await tester.pumpAndSettle();
      expect(resolvedId, jobResult.id);
      expect(find.byType(JobDetailPage), findsOneWidget);
      expect(find.text('Descrição completa da vaga.'), findsOneWidget);
      expect(find.text('Empresa Exemplo'), findsOneWidget);
      expect(find.text('Centro'), findsOneWidget);
      expect(find.text('CLT'), findsOneWidget);
      expect(find.text('5511999999999'), findsNothing);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('auxiliar'), findsOneWidget);
      expect(find.text('Empregos'), findsOneWidget);
      expect(find.text(jobResult.title), findsOneWidget);
    },
  );
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
