import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';

void main() {
  test('public feeds replay recent data before refreshing it', () async {
    final cache = PublicContentFeedCache();
    final source = Object();
    final firstLoad = Completer<PublicContentSnapshot>();
    final refreshLoad = Completer<PublicContentSnapshot>();
    var loadCount = 0;
    Future<PublicContentSnapshot> load() {
      loadCount++;
      return loadCount == 1 ? firstLoad.future : refreshLoad.future;
    }

    final initialValue = Completer<PublicContentSnapshot>();
    final initialSubscription = cache
        .watch(source: source, key: 'establishments', load: load)
        .listen(initialValue.complete);
    final initial = PublicContentSnapshot([]);
    firstLoad.complete(initial);
    expect(await initialValue.future, same(initial));
    await initialSubscription.cancel();

    final replayedValue = Completer<PublicContentSnapshot>();
    final refreshedValue = Completer<PublicContentSnapshot>();
    final replaySubscription = cache
        .watch(source: source, key: 'establishments', load: load)
        .listen((snapshot) {
          if (!replayedValue.isCompleted) {
            replayedValue.complete(snapshot);
          } else {
            refreshedValue.complete(snapshot);
          }
        });

    expect(await replayedValue.future, same(initial));
    expect(loadCount, 2);
    final updated = PublicContentSnapshot([]);
    refreshLoad.complete(updated);
    expect(await refreshedValue.future, same(updated));
    await replaySubscription.cancel();
  });

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
