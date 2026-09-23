import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_collections.dart';
import '../models/business.dart';

class BusinessRepository {
  BusinessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<Business>> watchPublishedBusinesses() => _firestore
      .collection(FirestoreCollections.establishments)
      .where('published', isEqualTo: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Business.fromFirestore).toList());

  static List<Business> featuredBusinesses(Iterable<Business> businesses) =>
      businesses.where((business) => business.featured).toList();
}
