import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_collections.dart';
import '../../../core/config/beta_environment.dart';
import '../../../core/content/beta_public_catalog.dart';
import '../../../core/content/premium_projection_result.dart';
import '../models/business.dart';
import '../../../core/content/public_content_repository.dart';
import '../../../core/content/public_content_detail_repository.dart';

class BusinessRepository {
  BusinessRepository({
    FirebaseFirestore? firestore,
    PublicContentDetailRepository? details,
    PremiumProjectionLoader? premiumProjectionLoader,
    BasicProjectionLoader? basicProjectionLoader,
  }) : _firestore = firestore,
       _details = details ?? PublicContentDetailRepository(),
       _premiumProjectionLoader = premiumProjectionLoader,
       _basicProjectionLoader = basicProjectionLoader;

  final FirebaseFirestore? _firestore;
  final PublicContentDetailRepository _details;
  final PremiumProjectionLoader? _premiumProjectionLoader;
  final BasicProjectionLoader? _basicProjectionLoader;

  /// Resolve the Basic projection and its Premium complement for non-route
  /// consumers that require a complete selected detail.
  Future<Business?> getPublicBusiness(String id) async {
    final basic = await getBasicPublicBusiness(id);
    if (basic == null) return null;
    return _withPremiumIfAvailable(basic);
  }

  /// Resolves only the public Basic projection. Navigation routes use this
  /// first so a slow or denied Premium sibling cannot block a Basic profile.
  Future<Business?> getBasicPublicBusiness(String id) async {
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      return null;
    }
    final data =
        await (_basicProjectionLoader?.call(id) ??
            _details.resolve(
              collection: FirestoreCollections.establishments,
              id: id,
            ));
    if (data == null) return null;
    return Business.fromBasicProjection(id, data);
  }

  /// Reads one Premium sibling only for a selected, already-resolved Basic
  /// detail. Never queries a collection or reads the canonical document.
  Future<PremiumProjectionResult> getPremiumProjectionForBasic(
    String id,
  ) async {
    if (id.trim().isEmpty || id.contains('/')) {
      return const PremiumProjectionResult(
        status: PremiumProjectionStatus.invalid,
      );
    }
    try {
      final injected = _premiumProjectionLoader;
      if (injected != null) return await injected(id);
      if (!BetaEnvironment.enabled) {
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.missing,
        );
      }
      final firestore = _firestore ?? FirebaseFirestore.instance;
      return await BetaPublicCatalog(firestore).getPremiumEstablishment(id);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.permissionDenied,
        );
      }
      return const PremiumProjectionResult(
        status: PremiumProjectionStatus.unavailable,
      );
    } catch (_) {
      return const PremiumProjectionResult(
        status: PremiumProjectionStatus.unavailable,
      );
    }
  }

  Future<Business> _withPremiumIfAvailable(Business basic) async {
    final projection = await getPremiumProjectionForBasic(basic.id);
    final expiry = projection.premiumUntil;
    if (!projection.isAvailable ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      return basic;
    }
    return basic.withPremiumProjection(projection.data, premiumUntil: expiry);
  }

  Stream<List<Business>> watchPublishedBusinesses() =>
      watchPublicContent(
        FirestoreCollections.establishments,
        firestore: _firestore ?? FirebaseFirestore.instance,
      ).map(
        (snapshot) => snapshot.docs
            .map((doc) => Business.fromBasicProjection(doc.id, doc.data()))
            .toList(),
      );

  static List<Business> featuredBusinesses(Iterable<Business> businesses) =>
      businesses.where((business) => business.featured).toList();
}

typedef PremiumProjectionLoader =
    Future<PremiumProjectionResult> Function(String establishmentId);
typedef BasicProjectionLoader =
    Future<Map<String, dynamic>?> Function(String establishmentId);
