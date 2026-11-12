import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/models/ad_business_option.dart';

void main() {
  group('ad business destination validation', () {
    test('accepts only a non-empty Firestore document ID', () {
      expect(validAdBusinessId('business-123'), 'business-123');
      expect(validAdBusinessId(' business-123 '), isNull);
      expect(validAdBusinessId(''), isNull);
      expect(validAdBusinessId('  '), isNull);
      expect(validAdBusinessId('../other'), isNull);
      expect(validAdBusinessId('folder/business'), isNull);
      expect(validAdBusinessId('x' * 129), isNull);
    });

    test('rejects explicitly unpublished, inactive and removed targets', () {
      expect(isEligibleAdBusiness({'published': true, 'active': true}), isTrue);
      expect(isEligibleAdBusiness({'published': false}), isFalse);
      expect(isEligibleAdBusiness({'active': false}), isFalse);
      expect(isEligibleAdBusiness({'deleted': true}), isFalse);
      expect(isEligibleAdBusiness({'deletedAt': DateTime.utc(2026)}), isFalse);
      expect(isEligibleAdBusiness(const {}), isTrue);
    });

    test('shows only ads that reference a currently public business', () {
      final publicBusinesses = <String, Map<String, dynamic>>{
        'public-1': {'published': true, 'active': true},
        'draft-1': {'published': false, 'active': true},
        'inactive-1': {'published': true, 'active': false},
        'deleted-1': {'published': false, 'active': false, 'deleted': true},
      };

      expect(
        hasVisibleAdDestination({'businessId': 'public-1'}, publicBusinesses),
        isTrue,
      );
      for (final id in ['draft-1', 'inactive-1', 'deleted-1', 'missing']) {
        expect(
          hasVisibleAdDestination({'businessId': id}, publicBusinesses),
          isFalse,
        );
      }
      expect(
        hasVisibleAdDestination({
          'link': 'https://example.com',
        }, publicBusinesses),
        isFalse,
      );
      expect(
        hasVisibleAdDestination({'businessId': '../bad'}, publicBusinesses),
        isFalse,
      );
    });
  });
}
