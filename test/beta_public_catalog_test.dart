import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/beta_public_catalog.dart';
import 'package:tudo_aqui_macacu/core/content/premium_projection_result.dart';

void main() {
  test('Basic establishment projection rejects commercial details', () {
    expect(
      BetaPublicCatalog.containsOnlyBasicEstablishmentFields(const {
        'name': 'Loja',
        'address': 'Centro',
        'phone': '2222-3333',
        'category': 'Comércio',
      }),
      isTrue,
    );
    expect(
      BetaPublicCatalog.containsOnlyBasicEstablishmentFields(const {
        'name': 'Loja',
        'description': 'Premium não pode entrar na lista',
      }),
      isFalse,
    );
  });

  group('BetaPublicCatalog.storageCollectionNameFor', () {
    test(
      'maps the existing establishments catalog to the Basic projection',
      () {
        expect(
          BetaPublicCatalog.storageCollectionNameFor('establishments'),
          'establishments_basic',
        );
      },
    );

    test('preserves physical paths for other catalog collections', () {
      expect(BetaPublicCatalog.storageCollectionNameFor('events'), 'events');
      expect(BetaPublicCatalog.storageCollectionNameFor('ads'), 'ads');
    });

    test('rejects collections outside the current public catalog contract', () {
      expect(
        () => BetaPublicCatalog.storageCollectionNameFor('users'),
        throwsArgumentError,
      );
    });
  });

  group('Premium establishment envelope', () {
    final now = DateTime.utc(2026, 11, 12, 12);

    Map<String, dynamic> envelope({
      String sourceId = 'loja-1',
      DateTime? premiumUntil,
      Map<String, dynamic>? publicData,
    }) => {
      'visibility': 'public',
      'sourceId': sourceId,
      'schemaVersion': 1,
      'updatedAt': Timestamp.fromDate(now),
      'listingTier': 'premium',
      'premiumUntil': Timestamp.fromDate(
        premiumUntil ?? DateTime.utc(2026, 11, 13),
      ),
      'publicData': publicData ?? const {'description': 'Conteúdo comercial'},
    };

    test('accepts a future entitlement and returns only its complement', () {
      final result = BetaPublicCatalog.decodePremiumEstablishmentEnvelope(
        envelope(),
        expectedId: 'loja-1',
        now: now,
      );

      expect(result.status, PremiumProjectionStatus.available);
      expect(result.data, {'description': 'Conteúdo comercial'});
      expect(result.premiumUntil, DateTime.utc(2026, 11, 13));
    });

    test('treats the exact expiry instant as Basic', () {
      final result = BetaPublicCatalog.decodePremiumEstablishmentEnvelope(
        envelope(premiumUntil: now),
        expectedId: 'loja-1',
        now: now,
      );

      expect(result.status, PremiumProjectionStatus.expired);
      expect(result.data, isEmpty);
    });

    test(
      'rejects a mismatched ID and any field outside the Premium allowlist',
      () {
        final mismatched = BetaPublicCatalog.decodePremiumEstablishmentEnvelope(
          envelope(sourceId: 'outra-loja'),
          expectedId: 'loja-1',
          now: now,
        );
        final withBasicContact =
            BetaPublicCatalog.decodePremiumEstablishmentEnvelope(
              envelope(
                publicData: const {
                  'description': 'Premium',
                  'ownerUid': 'must-not-be-exposed',
                },
              ),
              expectedId: 'loja-1',
              now: now,
            );

        expect(mismatched.status, PremiumProjectionStatus.invalid);
        expect(withBasicContact.status, PremiumProjectionStatus.invalid);
      },
    );
  });
}
