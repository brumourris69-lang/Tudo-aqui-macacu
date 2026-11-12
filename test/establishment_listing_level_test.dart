import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/establishment_listing_level.dart';

void main() {
  group('EstablishmentListingLevel', () {
    final now = DateTime.utc(2026, 11, 12, 12);

    test('Básico é o nível efetivo para cadastro básico', () {
      const level = EstablishmentListingLevel(listingTier: ListingTier.basic);

      expect(level.listingTier, ListingTier.basic);
      expect(level.effectiveTierAt(now), ListingTier.basic);
    });

    test('Premium futuro é efetivo e mantém a data em UTC', () {
      final level = EstablishmentListingLevel.fromMap({
        'listingTier': 'premium',
        'premiumUntil': Timestamp.fromDate(now.add(const Duration(days: 30))),
      });

      expect(level.listingTier, ListingTier.premium);
      expect(level.premiumUntil, now.add(const Duration(days: 30)));
      expect(level.effectiveTierAt(now), ListingTier.premium);
      expect(level.canBeSavedAt(now), isTrue);
    });

    test('Premium expira exatamente no instante limite', () {
      final level = EstablishmentListingLevel.fromMap({
        'listingTier': 'premium',
        'premiumUntil': Timestamp.fromDate(now),
      });

      expect(level.listingTier, ListingTier.premium);
      expect(level.effectiveTierAt(now), ListingTier.basic);
      expect(level.canBeSavedAt(now), isFalse);
    });

    test(
      'Premium vencido rebaixa sem apagar o nível contratado nem os dados',
      () {
        final canonical = <String, dynamic>{
          'name': 'Comércio legado',
          'category': 'Comércio',
          'galleryUrls': ['https://example.test/photo.jpg'],
          'listingTier': 'premium',
          'premiumUntil': Timestamp.fromDate(
            now.subtract(const Duration(seconds: 1)),
          ),
        };
        final level = EstablishmentListingLevel.fromMap(canonical);

        expect(level.listingTier, ListingTier.premium);
        expect(level.effectiveTierAt(now), ListingTier.basic);
        expect(canonical['galleryUrls'], ['https://example.test/photo.jpg']);
        expect(canonical['category'], 'Comércio');
        expect(level.toMap()['listingTier'], 'premium');
        expect(level.toMap()['premiumUntil'], isA<Timestamp>());
      },
    );

    test('campo de nível ausente mantém compatibilidade como Básico', () {
      final level = EstablishmentListingLevel.fromMap(const {
        'name': 'Cadastro antigo',
        'category': 'Serviços',
      });

      expect(level.listingTier, ListingTier.basic);
      expect(level.premiumUntil, isNull);
      expect(level.effectiveTierAt(now), ListingTier.basic);
    });

    test('nível desconhecido ou data malformada não concede Premium', () {
      final unknownTier = EstablishmentListingLevel.fromMap({
        'listingTier': 'gold',
        'premiumUntil': Timestamp.fromDate(now.add(const Duration(days: 1))),
      });
      final invalidExpiry = EstablishmentListingLevel.fromMap({
        'listingTier': 'premium',
        'premiumUntil': '2099-01-01T00:00:00Z',
      });

      expect(unknownTier.listingTier, ListingTier.basic);
      expect(unknownTier.effectiveTierAt(now), ListingTier.basic);
      expect(invalidExpiry.listingTier, ListingTier.premium);
      expect(invalidExpiry.premiumUntil, isNull);
      expect(invalidExpiry.effectiveTierAt(now), ListingTier.basic);
      expect(invalidExpiry.canBeSavedAt(now), isFalse);
    });

    test('Básico pode ser salvo sem vencimento Premium', () {
      const level = EstablishmentListingLevel(listingTier: ListingTier.basic);

      expect(level.canBeSavedAt(now), isTrue);
    });

    test('serialização usa os campos definidos e Timestamp UTC', () {
      final expiry = DateTime(2026, 12, 12, 9);
      const level = EstablishmentListingLevel(listingTier: ListingTier.premium);
      final serialized = EstablishmentListingLevel(
        listingTier: level.listingTier,
        premiumUntil: expiry,
      ).toMap();

      expect(serialized.keys, containsAll(['listingTier', 'premiumUntil']));
      expect(serialized['listingTier'], 'premium');
      expect(
        (serialized['premiumUntil'] as Timestamp).toDate().toUtc(),
        expiry.toUtc(),
      );
    });

    test(
      'nível comercial separado preserva ID e categoria do modelo atual',
      () {
        final business = Business.fromData('mercado-central', {
          'name': 'Mercado Central',
          'category': 'Comércio',
          'location': 'Centro',
          'listingTier': 'premium',
          'premiumUntil': Timestamp.fromDate(now.add(const Duration(days: 1))),
        });
        final level = EstablishmentListingLevel.fromMap({
          'listingTier': 'premium',
          'premiumUntil': Timestamp.fromDate(now.add(const Duration(days: 1))),
        });

        expect(business.id, 'mercado-central');
        expect(business.category, 'Comércio');
        expect(level.effectiveTierAt(now), ListingTier.premium);
      },
    );
  });
}
