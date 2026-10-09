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

    // Reuse Business parsing/media conventions, with only display fields.
    // Do not attach the raw source map or a Business carrying contact fields.
    final business = Business.fromData(documentId, {
      'name': name,
      'category': text('category'),
      'subcategory': text('subcategory'),
      'shortDescription': text('shortDescription').trim().isNotEmpty
          ? text('shortDescription')
          : text('description'),
      'imageUrl': text('imageUrl'),
      'logoUrl': text('logoUrl'),
    });
    final description = business.description
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final runes = description.runes.toList();
    final summary = runes.length <= 180
        ? description
        : '${String.fromCharCodes(runes.take(179))}…';
    String image(String value) {
      final uri = Uri.tryParse(value);
      return uri != null &&
              (uri.scheme == 'https' || uri.scheme == 'http') &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? value
          : '';
    }

    final cover = image(business.imageUrl);
    return SearchResult(
      id: business.id,
      sourceCollection: FirestoreCollections.establishments,
      title: business.name,
      summary: summary,
      category: business.category,
      subcategory: business.subcategory,
      imageUrl: cover.isNotEmpty ? cover : image(business.logoUrl),
      type: SearchResultType.establishment,
      destination: SearchDestination.businessProfile,
    );
  }
}
