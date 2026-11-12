import '../../../core/config/firestore_collections.dart';
import '../../businesses/models/business.dart';
import '../models/search_result.dart';
import '../policies/business_search_policy.dart';

/// Pure projection of supplied data. Never initializes Firebase or reads data.
abstract final class BusinessSearchAdapter {
  static SearchResult? fromData(
    String documentId,
    Map<String, dynamic> data, {
    required DateTime now,
  }) {
    if (documentId.trim().isEmpty ||
        BusinessSearchPolicy.eligibility(data, now: now) !=
            PublicEligibility.eligible) {
      return null;
    }
    String text(String key) => data[key] is String ? data[key] as String : '';
    final name = text('name').trim().isNotEmpty ? text('name') : text('title');
    if (name.trim().isEmpty) return null;

    // Public search is part of the Basic catalog. Descriptions, images and
    // commercial links are never copied into search results or its index.
    final business = Business.fromBasicProjection(documentId, {
      'name': name,
      'category': text('category'),
      'subcategory': text('subcategory'),
      'address': text('address').trim().isNotEmpty
          ? text('address')
          : text('location'),
    });
    final summary = business.location.trim();
    return SearchResult(
      id: business.id,
      sourceCollection: FirestoreCollections.establishments,
      title: business.name,
      summary: summary,
      category: business.category,
      subcategory: business.subcategory,
      imageUrl: '',
      type: SearchResultType.establishment,
      destination: SearchDestination.businessProfile,
    );
  }
}
