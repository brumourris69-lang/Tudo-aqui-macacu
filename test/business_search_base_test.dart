import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/adapters/business_search_adapter.dart';
import 'package:tudo_aqui_macacu/features/search/models/search_result.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/utils/search_normalization.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart' show catalog;

void main() {
  final now = DateTime.utc(2026, 10, 8, 15);
  Map<String, dynamic> document([Map<String, dynamic> extra = const {}]) => {
    'published': true,
    'name': 'Elétrica Vieira',
    'category': 'Serviços',
    'subcategory': 'Eletricista',
    ...extra,
  };
  SearchResult? project(
    Map<String, dynamic> data, {
    String id = 'original-id',
  }) => BusinessSearchAdapter.fromData(id, data, now: now);

  group('normalization', () {
    test('removes Portuguese accents and case', () {
      expect(normalizeSearchText('Elétrica Vieira'), 'eletrica vieira');
      expect(
        normalizeSearchText('ÁGUA Ação Órgãos Saúde Ç'),
        'agua acao orgaos saude c',
      );
      expect(normalizeSearchText('E\u0301le\u0301trica'), 'eletrica');
    });
    test('normalizes spaces and punctuation without changing source', () {
      const source = '  Elétrica\nVieira — ÁGUA\t 24h!  ';
      expect(normalizeSearchText(source), 'eletrica vieira agua 24h');
      expect(source, contains('Elétrica'));
    });
    test('prepares unique immutable words and handles empty input', () {
      final words = prepareSearchTerms('Elétrica elétrica VIEIRA');
      expect(words, ['eletrica', 'vieira']);
      expect(() => words.add('new'), throwsUnsupportedError);
      expect(prepareSearchTerms(' \n ! '), isEmpty);
    });
  });

  group('category mapping', () {
    test('every commerce/service mapping uses a real catalog category', () {
      final names = catalog.map((category) => category.name).toSet();
      expect(
        names.containsAll(BusinessSearchPolicy.commerceCategories),
        isTrue,
      );
      expect(names.containsAll(BusinessSearchPolicy.serviceCategories), isTrue);
    });
    test(
      'commerce includes food, technology and other commercial categories',
      () {
        for (final category in BusinessSearchPolicy.commerceCategories) {
          expect(
            BusinessSearchPolicy.matchesCategory(
              category,
              BusinessSearchFilter.commerce,
            ),
            isTrue,
            reason: category,
          );
          expect(
            BusinessSearchPolicy.matchesCategory(
              category,
              BusinessSearchFilter.services,
            ),
            isFalse,
            reason: category,
          );
        }
        expect(
          BusinessSearchPolicy.matchesCategory(
            '  TECNOLOGIA ',
            BusinessSearchFilter.commerce,
          ),
          isTrue,
        );
      },
    );
    test('services includes both services and professionals', () {
      for (final category in BusinessSearchPolicy.serviceCategories) {
        expect(
          BusinessSearchPolicy.matchesCategory(
            category,
            BusinessSearchFilter.services,
          ),
          isTrue,
        );
        expect(
          BusinessSearchPolicy.matchesCategory(
            category,
            BusinessSearchFilter.commerce,
          ),
          isFalse,
        );
      }
    });
    test('all preserves all catalog categories and unknown categories', () {
      for (final category in [
        ...catalog.map((item) => item.name),
        '',
        'Categoria futura',
      ]) {
        expect(
          BusinessSearchPolicy.matchesCategory(
            category,
            BusinessSearchFilter.all,
          ),
          isTrue,
        );
      }
      for (final category in [
        'Empregos',
        'Turismo',
        'Notícias',
        'Eventos',
        'Promoções',
        'Serviços úteis',
        'Categoria futura',
        '',
      ]) {
        expect(
          BusinessSearchPolicy.matchesCategory(
            category,
            BusinessSearchFilter.commerce,
          ),
          isFalse,
        );
        expect(
          BusinessSearchPolicy.matchesCategory(
            category,
            BusinessSearchFilter.services,
          ),
          isFalse,
        );
      }
    });
    test('ambiguous subcategory does not override its original parent', () {
      final result = project(
        document({
          'category': 'Tecnologia',
          'subcategory': 'Assistência técnica',
        }),
      )!;
      expect(result.category, 'Tecnologia');
      expect(result.subcategory, 'Assistência técnica');
      expect(
        BusinessSearchPolicy.matchesCategory(
          result.category,
          BusinessSearchFilter.commerce,
        ),
        isTrue,
      );
    });
  });

  group('public eligibility', () {
    test('published with optional fields absent is eligible', () {
      expect(
        BusinessSearchPolicy.eligibility(document(), now: now),
        PublicEligibility.eligible,
      );
      expect(project(document()), isNotNull);
    });
    test('unpublished is excluded', () {
      final data = document({'published': false});
      expect(
        BusinessSearchPolicy.eligibility(data, now: now),
        PublicEligibility.unpublished,
      );
      expect(project(data), isNull);
    });
    test('inactive is excluded', () {
      final data = document({'active': false});
      expect(
        BusinessSearchPolicy.eligibility(data, now: now),
        PublicEligibility.inactive,
      );
      expect(project(data), isNull);
    });
    test('past and exact-boundary expiry are excluded, future is eligible', () {
      for (final date in [now.subtract(const Duration(seconds: 1)), now]) {
        final data = document({'expiresAt': Timestamp.fromDate(date)});
        expect(
          BusinessSearchPolicy.eligibility(data, now: now),
          PublicEligibility.expired,
        );
        expect(project(data), isNull);
      }
      expect(
        project(
          document({
            'expiresAt': Timestamp.fromDate(
              now.add(const Duration(seconds: 1)),
            ),
          }),
        ),
        isNotNull,
      );
    });
    test('missing or malformed visibility remains pending', () {
      final missing = document()..remove('published');
      for (final data in [
        missing,
        document({'published': 'true'}),
        document({'published': null}),
        document({'active': null}),
        document({'active': 'true'}),
        document({'expiresAt': '2027-01-01'}),
        document({'expiresAt': null}),
      ]) {
        expect(
          BusinessSearchPolicy.eligibility(data, now: now),
          PublicEligibility.pending,
        );
        expect(project(data), isNull);
      }
    });
    test('closed establishment remains public', () {
      expect(project(document({'open': false, 'active': true})), isNotNull);
    });
  });

  group('public projection', () {
    test(
      'preserves original ID, source, category and existing destination',
      () {
        final data = document({
          'id': 'injected-id',
          'sourceCollection': 'users',
        });
        final result = project(data, id: 'AbC_123')!;
        expect(result.id, 'AbC_123');
        expect(result.sourceCollection, 'establishments');
        expect(result.title, 'Elétrica Vieira');
        expect(result.type, SearchResultType.establishment);
        expect(result.destination, SearchDestination.businessProfile);
        expect(data['id'], 'injected-id');
      },
    );
    test('projects only allowlisted display fields', () {
      final result = project(
        document({
          'adminEmail': 'secret',
          'ownerUid': 'secret',
          'internalNotes': 'secret',
          'phone': 'secret',
          'whatsapp': 'secret',
          'contact': 'secret',
          'token': 'secret',
          'private': {'value': 'secret'},
        }),
      )!;
      expect(result.toMap().keys.toSet(), {
        'id',
        'sourceCollection',
        'title',
        'summary',
        'category',
        'subcategory',
        'imageUrl',
        'type',
        'destination',
      });
      expect(result.toMap().values.join(' '), isNot(contains('secret')));
    });
    test('missing optional display fields do not invent commerce category', () {
      final result = project({'published': true, 'title': 'Nome legado'})!;
      expect(result.title, 'Nome legado');
      expect(result.summary, isEmpty);
      expect(result.category, isEmpty);
      expect(result.subcategory, isEmpty);
      expect(result.imageUrl, isEmpty);
    });
    test('missing identity/name does not create a fictitious result', () {
      expect(project(document(), id: ''), isNull);
      expect(project({'published': true}), isNull);
    });
    test('summary is bounded, unicode safe and prefers short description', () {
      final result = project(
        document({
          'shortDescription': '${List.filled(181, '😀').join()}\n',
          'description': 'Long description',
        }),
      )!;
      expect(result.summary.runes.length, 180);
      expect(result.summary, endsWith('…'));
      expect(
        project(document({'description': ' Texto\n  público '}))!.summary,
        'Texto público',
      );
    });
    test('image uses existing Business mapping with safe logo fallback', () {
      expect(
        project(
          document({'imageUrl': 'https://example.com/public.png'}),
        )!.imageUrl,
        'https://example.com/public.png',
      );
      expect(
        project(
          document({
            'imageUrl': 'file:///private.png',
            'logoUrl': 'https://example.com/logo.png',
          }),
        )!.imageUrl,
        'https://example.com/logo.png',
      );
      expect(
        project(
          document({
            'imageUrl': 'https://secret:password@example.com/image.png',
          }),
        )!.imageUrl,
        isEmpty,
      );
    });
  });
}
