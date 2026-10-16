import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_collections.dart';
import '../models/business.dart';
import '../../../core/content/public_content_repository.dart';
import '../../../core/content/public_content_detail_repository.dart';

class BusinessRepository {
  BusinessRepository({
    FirebaseFirestore? firestore,
    PublicContentDetailRepository? details,
  }) : _firestore = firestore,
       _details = details ?? PublicContentDetailRepository();

  final FirebaseFirestore? _firestore;
  final PublicContentDetailRepository _details;

  /// Resolve only the selected public projection, never the raw Firestore doc.
  Future<Business?> getPublicBusiness(String id) async {
    if (id.isEmpty || id.contains('/')) return null;
    final data = await _details.resolve(
      collection: FirestoreCollections.establishments,
      id: id,
    );
    if (data == null) return null;
    return Business.fromData(id, data);
  }

  Stream<List<Business>> watchPublishedBusinesses() =>
      watchPublicContent(
        FirestoreCollections.establishments,
        firestore: _firestore ?? FirebaseFirestore.instance,
      ).map(
        (snapshot) => snapshot.docs
            .map((doc) => Business.fromData(doc.id, doc.data()))
            .toList(),
      );

  static List<Business> featuredBusinesses(Iterable<Business> businesses) =>
      businesses.where((business) => business.featured).toList();
}
