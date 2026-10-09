import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/search/infrastructure/business_search_index.dart';
import 'package:tudo_aqui_macacu/features/search/policies/business_search_policy.dart';
import 'package:tudo_aqui_macacu/features/search/utils/search_normalization.dart';

void main() {
  test(
    'Dart matches shared Node normalization category and projection fixtures',
    () {
      final fixture =
          jsonDecode(
                File(
                  'functions/test/fixtures/business_search_parity.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final sample in fixture['normalization'] as List) {
        expect(
          normalizeSearchText(sample['input'] as String),
          sample['expected'],
        );
      }
      for (final item
          in (fixture['categories'] as Map<String, dynamic>).entries) {
        final group =
            BusinessSearchPolicy.matchesCategory(
              item.key,
              BusinessSearchFilter.services,
            )
            ? 'services'
            : BusinessSearchPolicy.matchesCategory(
                item.key,
                BusinessSearchFilter.commerce,
              )
            ? 'commerce'
            : 'other';
        expect(group, item.value);
      }
      final sample = fixture['projection'] as Map<String, dynamic>;
      final result = BusinessSearchIndexEntry.build(
        sample['id'] as String,
        sample['data'] as Map<String, dynamic>,
        now: DateTime.utc(2026, 10, 8),
        authorizeImage: (_) => false,
      )!;
      expect(result.result.toMap(), sample['expected']);
      expect(result.terms, sample['terms']);
    },
  );
}
