import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/premium_projection_result.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/establishment_listing_level.dart';
import 'package:tudo_aqui_macacu/features/businesses/repositories/business_repository.dart';

void main() {
  const basicData = <String, dynamic>{
    'name': 'Loja Básica',
    'category': 'Comércio',
    'subcategory': 'Mercado',
    'address': 'Centro',
    'phone': '(21) 2222-3333',
  };

  Future<Map<String, dynamic>?> basic(Map<String, dynamic> data) async => data;

  test('public listing parser keeps only Basic fields', () {
    final business = Business.fromBasicProjection('loja-1', {
      ...basicData,
      'description': 'deve ser descartada',
      'imageUrl': 'https://example.test/image.png',
      'whatsapp': '5521999999999',
      'maps': 'https://maps.example.test',
      'hours': 'todos os dias',
    });

    expect(business.listingTier, ListingTier.basic);
    expect(business.description, isEmpty);
    expect(business.displayImageUrls, isEmpty);
    expect(business.whatsapp, isEmpty);
    expect(business.maps, isEmpty);
    expect(business.hours, isEmpty);
    expect(business.phone, basicData['phone']);
    expect(business.categoryLabel, 'Comércio · Mercado');
  });

  test(
    'public detail loads Premium by the same ID and merges allowlisted data',
    () async {
      var requestedId = '';
      final repository = BusinessRepository(
        basicProjectionLoader: (_) => basic(basicData),
        premiumProjectionLoader: (id) async {
          requestedId = id;
          return PremiumProjectionResult.available(
            premiumUntil: DateTime.utc(2099),
            data: const {
              'description': 'Atendimento completo.',
              'imageUrl': 'https://example.test/cover.png',
              'whatsapp': '5521999999999',
            },
          );
        },
      );

      final business = await repository.getPublicBusiness('loja-1');

      expect(requestedId, 'loja-1');
      expect(business!.listingTier, ListingTier.premium);
      expect(business.description, 'Atendimento completo.');
      expect(business.displayImageUrls, ['https://example.test/cover.png']);
      expect(business.phone, basicData['phone']);
    },
  );

  for (final unavailable in [
    PremiumProjectionStatus.missing,
    PremiumProjectionStatus.expired,
    PremiumProjectionStatus.permissionDenied,
    PremiumProjectionStatus.unavailable,
    PremiumProjectionStatus.invalid,
  ]) {
    test('detail falls back to Basic when Premium is $unavailable', () async {
      final repository = BusinessRepository(
        basicProjectionLoader: (_) => basic(basicData),
        premiumProjectionLoader: (_) async =>
            PremiumProjectionResult(status: unavailable),
      );

      final business = await repository.getPublicBusiness('loja-1');

      expect(business, isNotNull);
      expect(business!.listingTier, ListingTier.basic);
      expect(business.name, 'Loja Básica');
      expect(business.displayImageUrls, isEmpty);
      expect(business.whatsapp, isEmpty);
    });
  }

  test(
    'unavailable Basic projection is not replaced with premium or canonical data',
    () async {
      var premiumReads = 0;
      final repository = BusinessRepository(
        basicProjectionLoader: (_) async => null,
        premiumProjectionLoader: (_) async {
          premiumReads++;
          return PremiumProjectionResult.available(
            premiumUntil: DateTime.utc(2099),
            data: const {'description': 'Premium'},
          );
        },
      );

      expect(await repository.getPublicBusiness('loja-1'), isNull);
      expect(premiumReads, 0);
    },
  );

  test('invalid Basic ID never starts either projection read', () async {
    var reads = 0;
    final repository = BusinessRepository(
      basicProjectionLoader: (_) async {
        reads++;
        return basicData;
      },
      premiumProjectionLoader: (_) async {
        reads++;
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.missing,
        );
      },
    );

    expect(await repository.getPublicBusiness('../other'), isNull);
    expect(reads, 0);
  });
}
