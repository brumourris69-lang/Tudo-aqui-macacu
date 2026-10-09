import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_collections.dart';
import '../models/business.dart';
import '../../search/policies/business_search_policy.dart';

class BusinessRepository {
  BusinessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Resolve only the selected original document, without a collection scan.
  Future<Business?> getPublicBusiness(String id) async {
    if (id.isEmpty || id.contains('/')) return null;
    final document = await _firestore
        .collection(FirestoreCollections.establishments)
        .doc(id)
        .get(const GetOptions(source: Source.server));
    final data = document.data();
    if (data == null ||
        BusinessSearchPolicy.eligibility(data, now: DateTime.now()) !=
            PublicEligibility.eligible) {
      return null;
    }
    return Business.fromFirestore(document);
  }

  Stream<List<Business>> watchPublishedBusinesses() => _firestore
      .collection(FirestoreCollections.establishments)
      .where('published', isEqualTo: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Business.fromFirestore).toList());

  static List<Business> featuredBusinesses(Iterable<Business> businesses) =>
      businesses.where((business) => business.featured).toList();
}
