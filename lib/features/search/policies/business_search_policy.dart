import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/search_normalization.dart';

enum BusinessSearchFilter { all, commerce, services }

enum PublicEligibility { eligible, unpublished, inactive, expired, pending }

/// Explicit parent-category policy, without changing catalog identifiers.
/// Mixed categories retain their existing parent: subcategories do not guess
/// whether a particular establishment sells products or supplies services.
abstract final class BusinessSearchPolicy {
  static const commerceCategories = {
    'Comércio',
    'Onde comer?',
    'Saúde',
    'Imóveis',
    'Veículos',
    'Pets',
    'Beleza',
    'Academias',
    'Educação',
    'Hospedagem',
    'Tecnologia',
  };
  static const serviceCategories = {'Serviços', 'Profissionais'};

  static bool matchesCategory(String category, BusinessSearchFilter filter) {
    if (filter == BusinessSearchFilter.all) return true;
    final candidates = filter == BusinessSearchFilter.commerce
        ? commerceCategories
        : serviceCategories;
    final normalized = normalizeSearchText(category);
    return candidates.any((name) => normalizeSearchText(name) == normalized);
  }

  /// Business.open is intentionally ignored: closed does not mean unpublished.
  /// Missing optional active/expiry impose no restriction; malformed values
  /// are pending rather than silently interpreted as public.
  static PublicEligibility eligibility(
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    if (data['published'] == false) return PublicEligibility.unpublished;
    if (data['active'] == false) return PublicEligibility.inactive;
    final expiry = data['expiresAt'];
    if (expiry is Timestamp && !expiry.toDate().isAfter(now)) {
      return PublicEligibility.expired;
    }
    if (data['published'] != true ||
        (data.containsKey('active') && data['active'] is! bool) ||
        (data.containsKey('expiresAt') && expiry is! Timestamp)) {
      return PublicEligibility.pending;
    }
    return PublicEligibility.eligible;
  }
}
