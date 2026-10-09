enum SearchResultType { establishment }

enum SearchDestination { businessProfile }

/// Public display data only. Navigation resolves the original document later
/// using its collection/ID and the existing BusinessProfile flow.
class SearchResult {
  const SearchResult({
    required this.id,
    required this.sourceCollection,
    required this.title,
    required this.summary,
    required this.category,
    required this.subcategory,
    required this.type,
    required this.destination,
    this.imageUrl = '',
  });

  final String id, sourceCollection, title, summary, category, subcategory;
  final String imageUrl;
  final SearchResultType type;
  final SearchDestination destination;

  Map<String, String> toMap() => {
    'id': id,
    'sourceCollection': sourceCollection,
    'title': title,
    'summary': summary,
    'category': category,
    'subcategory': subcategory,
    'imageUrl': imageUrl,
    'type': type.name,
    'destination': destination.name,
  };
}
