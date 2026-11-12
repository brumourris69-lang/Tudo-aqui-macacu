import 'package:cloud_firestore/cloud_firestore.dart';

/// Commercial level stored on the single canonical establishment document.
enum ListingTier { basic, premium }

/// Field names used for the Admin-contracted listing level.
abstract final class EstablishmentListingLevelFields {
  static const listingTier = 'listingTier';
  static const premiumUntil = 'premiumUntil';
}

/// Contracted level and its optional Premium expiry.
///
/// [listingTier] records what the Admin assigned. [effectiveTierAt] separately
/// evaluates what may be displayed at a given instant. A Premium assignment
/// without a valid future [premiumUntil] therefore remains recorded as Premium
/// while its effective level is Basic.
class EstablishmentListingLevel {
  const EstablishmentListingLevel({
    required this.listingTier,
    this.premiumUntil,
  });

  final ListingTier listingTier;
  final DateTime? premiumUntil;

  factory EstablishmentListingLevel.fromMap(Map<String, dynamic> data) {
    final tierValue = data[EstablishmentListingLevelFields.listingTier];
    final tier = ListingTier.values.firstWhere(
      (value) => value.name == tierValue,
      orElse: () => ListingTier.basic,
    );

    final rawPremiumUntil = data[EstablishmentListingLevelFields.premiumUntil];
    final premiumUntil = switch (rawPremiumUntil) {
      Timestamp value => value.toDate().toUtc(),
      DateTime value => value.toUtc(),
      _ => null,
    };

    return EstablishmentListingLevel(
      listingTier: tier,
      premiumUntil: premiumUntil,
    );
  }

  /// Returns Premium only while its stored expiry is valid and strictly later
  /// than [now]. The caller supplies the clock to keep this policy testable.
  ListingTier effectiveTierAt(DateTime now) {
    final expiry = premiumUntil;
    if (listingTier != ListingTier.premium ||
        expiry == null ||
        !expiry.isAfter(now.toUtc())) {
      return ListingTier.basic;
    }
    return ListingTier.premium;
  }

  /// Whether the assigned level may be persisted at [now]. Basic has no
  /// expiry requirement; Premium must carry a strictly future instant.
  bool canBeSavedAt(DateTime now) =>
      listingTier == ListingTier.basic ||
      (premiumUntil != null && premiumUntil!.isAfter(now.toUtc()));

  /// Firestore representation of the two commercial fields.
  Map<String, Object?> toMap() => {
    EstablishmentListingLevelFields.listingTier: listingTier.name,
    EstablishmentListingLevelFields.premiumUntil: premiumUntil == null
        ? null
        : Timestamp.fromDate(premiumUntil!.toUtc()),
  };
}
