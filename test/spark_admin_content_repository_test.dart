import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/spark_admin_content_repository.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/establishment_listing_level.dart';

void main() {
  group('SparkAdminContentRepository environment selection', () {
    test('uses Rules-backed writes for Beta, local Spark and distribution', () {
      expect(
        SparkAdminContentRepository.shouldUseTransactionalAdmin(
          betaBuild: true,
          sparkDistributionBuild: false,
        ),
        isTrue,
      );
      expect(
        SparkAdminContentRepository.shouldUseTransactionalAdmin(
          betaBuild: false,
          sparkDistributionBuild: true,
        ),
        isTrue,
      );
      expect(
        SparkAdminContentRepository.shouldUseTransactionalAdmin(
          betaBuild: false,
          sparkDistributionBuild: false,
        ),
        isFalse,
      );
    });

    test('rejects conflicting Beta and Spark distribution identities', () {
      expect(
        () => SparkAdminContentRepository.shouldUseTransactionalAdmin(
          betaBuild: true,
          sparkDistributionBuild: true,
        ),
        throwsStateError,
      );
    });
  });

  group('SparkAdminContentRepository.publicProjection', () {
    test('copies only approved public content fields', () {
      final projection = SparkAdminContentRepository.publicProjection({
        'name': 'Padaria Central',
        'category': 'Alimentação',
        'imageUrl': 'https://example.test/cover.jpg',
        'businessId': 'business-123',
        'published': true,
        'active': true,
        'ownerEmail': 'private@example.test',
        'adminNotes': 'não publicar',
      }, collection: 'ads');

      expect(projection, {
        'name': 'Padaria Central',
        'category': 'Alimentação',
        'imageUrl': 'https://example.test/cover.jpg',
        'businessId': 'business-123',
      });
    });

    test('does not expose business IDs in unrelated catalog projections', () {
      expect(
        SparkAdminContentRepository.publicProjection({
          'title': 'Evento',
          'businessId': 'internal-only',
        }, collection: 'events'),
        {'title': 'Evento'},
      );
    });

    test(
      'establishment basic projection contains only textual basics and filter metadata',
      () {
        final projection = SparkAdminContentRepository.publicProjection({
          'name': 'Mercado Central',
          'address': 'Rua da Feira, 10',
          'location': 'Centro',
          'phone': '(21) 2222-0000',
          'category': 'Comércio',
          'subcategory': 'Mercado',
          'description': 'Premium description',
          'imageUrl': 'https://example.test/photo.jpg',
          'galleryUrls': ['https://example.test/1.jpg'],
          'options': {'nested': 'premium'},
          'instagram': 'https://instagram.example/market',
          'mapsUrl': 'https://maps.example/market',
          'ownerEmail': 'private@example.test',
        }, collection: 'establishments');

        expect(projection, {
          'name': 'Mercado Central',
          'address': 'Rua da Feira, 10',
          'location': 'Centro',
          'phone': '(21) 2222-0000',
          'category': 'Comércio',
          'subcategory': 'Mercado',
        });
      },
    );

    test(
      'premium projection requires an effective Premium level and expiry',
      () {
        final now = DateTime.utc(2026, 11, 12);
        final source = {
          'name': 'Mercado Central',
          'address': 'Rua da Feira, 10',
          'phone': '(21) 2222-0000',
          'category': 'Comércio',
          'listingTier': 'premium',
          'premiumUntil': Timestamp.fromDate(now.add(const Duration(days: 1))),
          'galleryUrls': ['https://example.test/1.jpg'],
          'instagram': 'https://instagram.example/market',
          'ownerEmail': 'private@example.test',
        };

        expect(
          SparkAdminContentRepository.premiumProjectionData(source, now: now),
          {
            'galleryUrls': ['https://example.test/1.jpg'],
            'instagram': 'https://instagram.example/market',
          },
        );
        expect(
          SparkAdminContentRepository.premiumProjectionData({
            ...source,
            'listingTier': 'basic',
          }, now: now),
          isNull,
        );
        expect(
          SparkAdminContentRepository.premiumProjectionData({
            ...source,
            'premiumUntil': Timestamp.fromDate(now),
          }, now: now),
          isNull,
        );
      },
    );

    test('Admin persistence rejects Premium without future expiry', () {
      final now = DateTime.utc(2026, 11, 12, 12);
      expect(
        () => SparkAdminContentRepository.validateListingLevelForSave({
          'listingTier': 'premium',
          'premiumUntil': Timestamp.fromDate(now),
        }, now: now),
        throwsFormatException,
      );
      expect(
        () => SparkAdminContentRepository.validateListingLevelForSave({
          'listingTier': 'premium',
        }, now: now),
        throwsFormatException,
      );
      expect(
        SparkAdminContentRepository.validateListingLevelForSave({
          'listingTier': 'basic',
        }, now: now).listingTier,
        ListingTier.basic,
      );
    });

    test('rejects a public projection without a title', () {
      expect(
        () => SparkAdminContentRepository.publicProjection({
          'description': 'sem nome',
        }),
        throwsFormatException,
      );
    });

    test('treats both deleted marker forms as permanent tombstones', () {
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({'deleted': true}),
        isTrue,
      );
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({
          'deleted': false,
          'deletedAt': DateTime.utc(2026, 10, 30),
        }),
        isTrue,
      );
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({
          'deleted': false,
          'deletedAt': null,
        }),
        isFalse,
      );
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({
          'deleted': false,
          'deletedAt': FieldValue.delete(),
        }),
        isFalse,
      );
      expect(SparkAdminContentRepository.isPermanentlyDeleted(null), isFalse);
    });
  });
}
