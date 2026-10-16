enum SearchResultType {
  establishment,
  tourism,
  news,
  jobs,
  events,
  utilities;

  // Preserve the existing backend wire value: "establishment".
  static const business = establishment;

  String get sourceCollection => switch (this) {
    establishment => 'establishments',
    tourism => 'routes',
    news => 'news',
    jobs => 'jobs',
    events => 'events',
    utilities => 'utilities',
  };
}

enum SearchDestination {
  businessProfile,
  touristSpotDetail,
  newsArticle,
  eventDetail,
  jobDetail,
  unavailable,
}

typedef SearchResultIdentity = ({String sourceCollection, String id});

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
    this.eventDate = '',
    this.location = '',
    this.company = '',
    this.employmentType = '',
  });

  final String id, sourceCollection, title, summary, category, subcategory;
  final String imageUrl;
  final String eventDate, location;
  final String company, employmentType;
  final SearchResultType type;
  final SearchDestination destination;

  SearchResultIdentity get identity =>
      (sourceCollection: sourceCollection, id: id);

  /// Only public, typed display fields are decoded. Unknown/private fields are
  /// never retained. Only existing detail destinations are accepted.
  factory SearchResult.fromMap(Map<dynamic, dynamic> data) {
    final type = switch (data['type']) {
      'establishment' || 'business' => SearchResultType.establishment,
      'tourism' => SearchResultType.tourism,
      'news' => SearchResultType.news,
      'jobs' => SearchResultType.jobs,
      'events' => SearchResultType.events,
      'utilities' => SearchResultType.utilities,
      _ => throw const FormatException('Tipo de resultado inválido.'),
    };
    final destination = switch (data['destination']) {
      'businessProfile' => SearchDestination.businessProfile,
      'touristSpotDetail' => SearchDestination.touristSpotDetail,
      'newsArticle' => SearchDestination.newsArticle,
      'eventDetail' => SearchDestination.eventDetail,
      'jobDetail' => SearchDestination.jobDetail,
      'unavailable' => SearchDestination.unavailable,
      _ => throw const FormatException('Destino de pesquisa inválido.'),
    };
    final id = data['id'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.contains('/') ||
        data['sourceCollection'] != type.sourceCollection ||
        (type == SearchResultType.establishment &&
            destination != SearchDestination.businessProfile) ||
        (type == SearchResultType.tourism &&
            destination != SearchDestination.touristSpotDetail) ||
        (type == SearchResultType.news &&
            destination != SearchDestination.newsArticle) ||
        (type == SearchResultType.events &&
            destination != SearchDestination.eventDetail) ||
        (type == SearchResultType.jobs &&
            destination != SearchDestination.jobDetail) ||
        (type != SearchResultType.establishment &&
            type != SearchResultType.tourism &&
            type != SearchResultType.news &&
            type != SearchResultType.events &&
            type != SearchResultType.jobs &&
            destination != SearchDestination.unavailable)) {
      throw const FormatException(
        'Identidade ou destino de pesquisa inválido.',
      );
    }
    String text(String key) {
      final value = data[key];
      if (value == null) return '';
      if (value is! String) {
        throw const FormatException('Campo público inválido.');
      }
      return value;
    }

    return SearchResult(
      id: id,
      sourceCollection: type.sourceCollection,
      title: text('title'),
      summary: text('summary'),
      category: text('category'),
      subcategory: text('subcategory'),
      imageUrl: text('imageUrl'),
      type: type,
      destination: destination,
      eventDate: type == SearchResultType.events ? text('eventDate') : '',
      location: type == SearchResultType.events || type == SearchResultType.jobs
          ? text('location')
          : '',
      company: type == SearchResultType.jobs ? text('company') : '',
      employmentType: type == SearchResultType.jobs
          ? text('employmentType')
          : '',
    );
  }

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
    if (type == SearchResultType.events) ...{
      'eventDate': eventDate,
      'location': location,
    },
    if (type == SearchResultType.jobs) ...{
      'company': company,
      'location': location,
      'employmentType': employmentType,
    },
  };
}
