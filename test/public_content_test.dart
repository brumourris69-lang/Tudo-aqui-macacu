import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';

void main() {
  test(
    'backend public timestamp decoder preserves timestamp type for existing models',
    () {
      final data =
          decodePublicValue({
                'title': 'Público',
                'expiresAt': {
                  '_publicTimestamp': [100, 0],
                },
                'options': ['A', 'B'],
              })
              as Map;
      expect(data['expiresAt'], Timestamp(100, 0));
      expect(data['options'], ['A', 'B']);
      expect(
        () => decodePublicValue({
          '_publicTimestamp': [1],
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'business profile eligibility preserves absent optional fields and closed business',
    () {
      final now = DateTime.utc(2026);
      expect(
        BusinessSearchPolicy.eligibility({
          'published': true,
          'open': false,
        }, now: now),
        PublicEligibility.eligible,
      );
      expect(
        BusinessSearchPolicy.eligibility({
          'published': true,
          'active': false,
        }, now: now),
        PublicEligibility.inactive,
      );
      expect(
        BusinessSearchPolicy.eligibility({
          'published': true,
          'expiresAt': Timestamp.fromDate(now),
        }, now: now),
        PublicEligibility.expired,
      );
      expect(
        BusinessSearchPolicy.eligibility({
          'published': true,
          'expiresAt': null,
        }, now: now),
        PublicEligibility.pending,
      );
    },
  );
}
