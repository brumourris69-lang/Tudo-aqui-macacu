import '../adapters/business_search_adapter.dart';
import '../models/search_result.dart';
import '../policies/business_search_policy.dart';
import '../utils/search_normalization.dart';

typedef PublicImageAuthorization = bool Function(String url);

/// Proposed private collection. No resource is created by this code.
const businessSearchIndexCollection = 'business_search_index';

class BusinessSearchIndexEntry {
  BusinessSearchIndexEntry._({
    required this.result,
    required this.terms,
    required this.prefixes,
    required this.group,
    required this.indexedAt,
  });

  final SearchResult result;
  final List<String> terms, prefixes;
  final String group;
  final DateTime indexedAt;
  String get indexId => 'establishments__${result.id}';

  static BusinessSearchIndexEntry? build(
    String id,
    Map<String, dynamic> source, {
    required DateTime now,
    required PublicImageAuthorization authorizeImage,
  }) {
    if (id.contains('/')) return null;
    final public = BusinessSearchAdapter.fromData(id, source, now: now);
    if (public == null) return null;
    final result = SearchResult(
      id: public.id,
      sourceCollection: public.sourceCollection,
      title: public.title,
      summary: public.summary,
      category: public.category,
      subcategory: public.subcategory,
      type: public.type,
      destination: public.destination,
      imageUrl: public.imageUrl.isNotEmpty && authorizeImage(public.imageUrl)
          ? public.imageUrl
          : '',
    );
    final terms =
        prepareSearchTerms(
              '${result.title} ${result.category} ${result.subcategory} ${result.summary}',
            )
            .take(64)
            .map((word) => word.length > 24 ? word.substring(0, 24) : word)
            .toSet()
            .toList()
          ..sort();
    final prefixes = <String>{};
    for (final term in terms) {
      for (var length = 2; length <= term.length; length++) {
        prefixes.add(term.substring(0, length));
      }
    }
    final group =
        BusinessSearchPolicy.matchesCategory(
          result.category,
          BusinessSearchFilter.services,
        )
        ? 'services'
        : BusinessSearchPolicy.matchesCategory(
            result.category,
            BusinessSearchFilter.commerce,
          )
        ? 'commerce'
        : 'other';
    return BusinessSearchIndexEntry._(
      result: result,
      terms: List.unmodifiable(terms),
      prefixes: List.unmodifiable(prefixes.toList()..sort()),
      group: group,
      indexedAt: now.toUtc(),
    );
  }

  /// The future Firestore adapter converts indexedAt to a server Timestamp.
  Map<String, Object> toMap() => {
    ...result.toMap(),
    'terms': terms,
    'prefixes': prefixes,
    'group': group,
    'schemaVersion': 1,
    'indexedAt': indexedAt,
  };
}
