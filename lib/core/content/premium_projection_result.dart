/// Outcome of a per-establishment Premium projection read.
///
/// Status is retained for diagnostics and tests; public UI always falls back to
/// the Basic projection for every non-[available] result.
enum PremiumProjectionStatus {
  available,
  missing,
  expired,
  permissionDenied,
  unavailable,
  invalid,
}

class PremiumProjectionResult {
  const PremiumProjectionResult({
    required this.status,
    this.data = const <String, dynamic>{},
    this.premiumUntil,
  });

  const PremiumProjectionResult.available({
    required Map<String, dynamic> data,
    required DateTime premiumUntil,
  }) : this(
         status: PremiumProjectionStatus.available,
         data: data,
         premiumUntil: premiumUntil,
       );

  final PremiumProjectionStatus status;
  final Map<String, dynamic> data;
  final DateTime? premiumUntil;

  bool get isAvailable =>
      status == PremiumProjectionStatus.available &&
      premiumUntil != null &&
      data.isNotEmpty;
}
