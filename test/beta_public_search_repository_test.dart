import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/models/search_result.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/beta_public_search_repository.dart';
import 'package:tudo_aqui_macacu/features/search/repositories/universal_search_repository.dart';

void main() {
  test(
    'Beta search uses only searchPublicContent and returns a bounded page',
    () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final repository = BetaPublicSearchRepository(
        invoke: (operation, data) async {
          calls.add((operation, data));
          return {
            'results': [
              {
                'id': 'shop-1',
                'sourceCollection': 'establishments',
                'title': 'Padaria Macacu',
                'summary': 'Pães e café',
                'category': 'Comércio',
                'subcategory': '',
                'imageUrl': '',
                'type': 'establishment',
                'destination': 'businessProfile',
                'privateEmail': 'must-not-be-decoded@example.invalid',
              },
            ],
            'nextCursor': null,
          };
        },
      );

      final page = await repository.search(
        BusinessSearchRequest(
          query: 'padaria',
          filter: BusinessSearchFilter.commerce,
        ),
      );

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'searchPublicContent');
      expect(calls.single.$2['filter'], 'commerce');
      expect(calls.single.$2['limit'], 20);
      expect(page.results.single.type, SearchResultType.establishment);
      expect(page.results.single.toMap().keys, isNot(contains('privateEmail')));
    },
  );

  test(
    'Beta search rejects private filters before invoking the backend',
    () async {
      var invoked = false;
      final repository = BetaPublicSearchRepository(
        invoke: (_, _) async {
          invoked = true;
          return const {};
        },
      );

      await expectLater(
        repository.search(
          BusinessSearchRequest(
            query: 'vaga',
            filter: BusinessSearchFilter.jobs,
          ),
        ),
        throwsArgumentError,
      );
      expect(invoked, isFalse);
    },
  );

  test(
    'Beta search rejects result sources outside the public search allowlist',
    () async {
      final repository = BetaPublicSearchRepository(
        invoke: (_, _) async => {
          'results': [
            {
              'id': 'news-1',
              'sourceCollection': 'news',
              'title': 'Notícia',
              'summary': '',
              'category': '',
              'subcategory': '',
              'imageUrl': '',
              'type': 'news',
              'destination': 'newsArticle',
            },
          ],
          'nextCursor': null,
        },
      );

      await expectLater(
        repository.search(BusinessSearchRequest(query: 'noticia')),
        throwsFormatException,
      );
    },
  );
}
