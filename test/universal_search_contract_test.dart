import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/models/search_result.dart';
import 'package:tudo_aqui_macacu/features/search/navigation/search_navigation.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/local_universal_search_repository.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/universal_search_repository.dart';

Map<String, String> wire(SearchResultType type) => {
  'id': 'same-original-id',
  'sourceCollection': type.sourceCollection,
  'type': type.name,
  'destination': switch (type) {
    SearchResultType.establishment => 'businessProfile',
    SearchResultType.tourism => 'touristSpotDetail',
    SearchResultType.news => 'newsArticle',
    SearchResultType.events => 'eventDetail',
    SearchResultType.jobs => 'jobDetail',
    _ => 'unavailable',
  },
  'title': 'Conteúdo fictício',
  'summary': 'Resumo público',
  'category': 'Categoria',
  if (type == SearchResultType.events) 'eventDate': '25/10/2026 às 19h',
  if (type == SearchResultType.events) 'location': 'Praça de Teste',
  if (type == SearchResultType.jobs) 'company': 'Empresa Exemplo',
  if (type == SearchResultType.jobs) 'location': 'Centro',
  if (type == SearchResultType.jobs) 'employmentType': 'CLT',
};

void main() {
  test('six public types round trip without retaining private metadata', () {
    for (final type in SearchResultType.values) {
      final result = SearchResult.fromMap({
        ...wire(type),
        'privateNotes': 'not public',
        'targetEmail': 'private@example.com',
        'admin': true,
      });
      expect(result.type, type);
      expect(result.id, 'same-original-id');
      expect(result.subcategory, '');
      expect(result.imageUrl, '');
      expect(
        result.toMap().keys,
        unorderedEquals([
          'id',
          'sourceCollection',
          'title',
          'summary',
          'category',
          'subcategory',
          'imageUrl',
          'type',
          'destination',
          if (type == SearchResultType.events) 'eventDate',
          if (type == SearchResultType.events) 'location',
          if (type == SearchResultType.jobs) 'company',
          if (type == SearchResultType.jobs) 'location',
          if (type == SearchResultType.jobs) 'employmentType',
        ]),
      );
      if (type == SearchResultType.events) {
        expect(result.eventDate, '25/10/2026 às 19h');
        expect(result.location, 'Praça de Teste');
      }
      if (type == SearchResultType.jobs) {
        expect(result.company, 'Empresa Exemplo');
        expect(result.location, 'Centro');
        expect(result.employmentType, 'CLT');
        expect(
          SearchNavigation.destinationFor(result),
          SearchDestination.jobDetail,
        );
      }
      expect(SearchResult.fromMap(result.toMap()).identity, result.identity);
    }
  });

  test('collection and ID jointly identify and deduplicate results', () {
    final business = SearchResult.fromMap(wire(SearchResultType.business));
    final tourism = SearchResult.fromMap(wire(SearchResultType.tourism));
    expect(business.identity, isNot(tourism.identity));
    expect({
      business.identity,
      tourism.identity,
      SearchResult.fromMap(business.toMap()).identity,
    }, hasLength(2));
  });

  test(
    'legacy business wire contract and original destination remain intact',
    () {
      final business = SearchResult.fromMap(wire(SearchResultType.business));
      expect(business.toMap()['type'], 'establishment');
      expect(
        SearchNavigation.destinationFor(business),
        SearchDestination.businessProfile,
      );
      final alias = SearchResult.fromMap({
        ...business.toMap(),
        'type': 'business',
      });
      expect(alias.type, business.type);
    },
  );

  test('business, tourism, news and events use their safe detail flows', () {
    final tourism = SearchResult.fromMap(wire(SearchResultType.tourism));
    expect(
      SearchNavigation.destinationFor(tourism),
      SearchDestination.touristSpotDetail,
    );
    expect(
      decodeLocalSearchPage({
        'results': [tourism.toMap()],
        'nextCursor': null,
      }, BusinessSearchRequest(query: 'teste')).results.single.type,
      SearchResultType.tourism,
    );
    final news = SearchResult.fromMap(wire(SearchResultType.news));
    expect(
      SearchNavigation.destinationFor(news),
      SearchDestination.newsArticle,
    );
    expect(
      decodeLocalSearchPage({
        'results': [news.toMap()],
        'nextCursor': null,
      }, BusinessSearchRequest(query: 'teste')).results.single.type,
      SearchResultType.news,
    );
    expect(
      decodeLocalSearchPage(
        {
          'results': [news.toMap()],
          'nextCursor': null,
        },
        BusinessSearchRequest(
          query: 'teste',
          filter: BusinessSearchFilter.news,
        ),
      ).results.single.type,
      SearchResultType.news,
    );
    final event = SearchResult.fromMap(wire(SearchResultType.events));
    expect(
      SearchNavigation.destinationFor(event),
      SearchDestination.eventDetail,
    );
    expect(
      decodeLocalSearchPage({
        'results': [event.toMap()],
        'nextCursor': null,
      }, BusinessSearchRequest(query: 'teste')).results.single.type,
      SearchResultType.events,
    );
    expect(
      decodeLocalSearchPage(
        {
          'results': [event.toMap()],
          'nextCursor': null,
        },
        BusinessSearchRequest(
          query: 'teste',
          filter: BusinessSearchFilter.events,
        ),
      ).results.single.type,
      SearchResultType.events,
    );
    for (final type in SearchResultType.values.where(
      (type) =>
          type != SearchResultType.establishment &&
          type != SearchResultType.tourism &&
          type != SearchResultType.news &&
          type != SearchResultType.events &&
          type != SearchResultType.jobs,
    )) {
      final result = SearchResult.fromMap(wire(type));
      expect(
        SearchNavigation.destinationFor(result),
        SearchDestination.unavailable,
      );
      expect(
        () => decodeLocalSearchPage({
          'results': [result.toMap()],
          'nextCursor': null,
        }, BusinessSearchRequest(query: 'teste')),
        throwsFormatException,
      );
    }
  });

  test(
    'jobs are accepted by Jobs and Todos with a secure detail destination',
    () {
      final job = SearchResult.fromMap(wire(SearchResultType.jobs));
      expect(SearchNavigation.destinationFor(job), SearchDestination.jobDetail);
      final request = BusinessSearchRequest(
        query: 'vaga',
        filter: BusinessSearchFilter.jobs,
      );
      final jobs = decodeLocalSearchPage({
        'results': [job.toMap()],
        'nextCursor': {
          'queryKey': request.queryKey,
          'lastIndexId': 'jobs__vaga-2',
        },
      }, request);
      expect(jobs.results.single.identity.sourceCollection, 'jobs');
      expect(jobs.nextCursor?.lastIndexId, 'jobs__vaga-2');
      final allRequest = BusinessSearchRequest(query: 'vaga');
      expect(
        decodeLocalSearchPage({
          'results': [job.toMap()],
          'nextCursor': {
            'queryKey': allRequest.queryKey,
            'lastIndexId': 'jobs__vaga-2',
          },
        }, allRequest).results.single.type,
        SearchResultType.jobs,
      );
      expect(
        () => BusinessSearchRequest(
          query: 'vaga',
          filter: BusinessSearchFilter.jobs,
          cursor: BusinessSearchCursor(
            request.queryKey,
            'events__wrong-source',
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'unknown types private sources invalid IDs and forged destinations fail closed',
    () {
      final business = wire(SearchResultType.business);
      for (final patch in [
        {'type': 'unknown'},
        {'sourceCollection': 'users'},
        {'sourceCollection': 'routes'},
        {'id': ''},
        {'id': 'users/private'},
        {'destination': 'arbitrary-route'},
        {'title': 123},
        {...wire(SearchResultType.tourism), 'destination': 'businessProfile'},
      ]) {
        expect(
          () => SearchResult.fromMap({...business, ...patch}),
          throwsFormatException,
        );
      }
      const forged = SearchResult(
        id: 'id',
        sourceCollection: 'users',
        title: 'Invalid',
        summary: '',
        category: '',
        subcategory: '',
        type: SearchResultType.business,
        destination: SearchDestination.businessProfile,
      );
      expect(
        SearchNavigation.destinationFor(forged),
        SearchDestination.unavailable,
      );
    },
  );

  test('query validation remains typed and compatible with ArgumentError', () {
    for (final query in [
      '',
      'a',
      'pão e café',
      'um dois tres quatro cinco',
      'x' * 25,
      'x' * 81,
    ]) {
      expect(
        () => BusinessSearchRequest(query: query),
        throwsA(isA<SearchQueryValidationException>()),
      );
      expect(() => BusinessSearchRequest(query: query), throwsArgumentError);
    }
    expect(BusinessSearchRequest(query: 'Elétrica Vieira').terms, [
      'eletrica',
      'vieira',
    ]);
    expect(
      () => BusinessSearchRequest(query: 'teste', limit: 21),
      throwsArgumentError,
    );
  });

  test('unified cursor accepts only a collection matching its filter', () {
    final all = BusinessSearchRequest(query: 'cachoeira');
    expect(
      () => BusinessSearchRequest(
        query: 'cachoeira',
        cursor: BusinessSearchCursor(all.queryKey, 'routes__a'),
      ),
      returnsNormally,
    );
    expect(
      () => BusinessSearchRequest(
        query: 'cachoeira',
        filter: BusinessSearchFilter.tourism,
        cursor: BusinessSearchCursor('tourism:cachoeira', 'establishments__a'),
      ),
      throwsArgumentError,
    );
    expect(
      () => BusinessSearchRequest(
        query: 'cachoeira',
        cursor: BusinessSearchCursor(all.queryKey, 'routes__'),
      ),
      throwsArgumentError,
    );
    expect(
      () => BusinessSearchRequest(
        query: 'cachoeira',
        filter: BusinessSearchFilter.events,
        cursor: BusinessSearchCursor('events:cachoeira', 'routes__wrong-type'),
      ),
      throwsArgumentError,
    );
    expect(
      () => BusinessSearchRequest(
        query: 'cachoeira',
        filter: BusinessSearchFilter.events,
        cursor: BusinessSearchCursor('events:cachoeira', 'events__valid'),
      ),
      returnsNormally,
    );
  });
}
