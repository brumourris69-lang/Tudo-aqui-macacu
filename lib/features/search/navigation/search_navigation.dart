import '../models/search_result.dart';

/// Dispatch policy, not an authorization check. Each enabled handler must
/// revalidate its original source before opening an existing detail screen.
abstract final class SearchNavigation {
  static SearchDestination destinationFor(SearchResult result) {
    if (result.id.trim().isEmpty ||
        result.id.contains('/') ||
        result.sourceCollection != result.type.sourceCollection) {
      return SearchDestination.unavailable;
    }
    return switch (result.type) {
      SearchResultType.establishment =>
        result.destination == SearchDestination.businessProfile
            ? result.destination
            : SearchDestination.unavailable,
      SearchResultType.tourism =>
        result.destination == SearchDestination.touristSpotDetail
            ? result.destination
            : SearchDestination.unavailable,
      SearchResultType.news =>
        result.destination == SearchDestination.newsArticle
            ? result.destination
            : SearchDestination.unavailable,
      SearchResultType.utilities => SearchDestination.unavailable,
      SearchResultType.events =>
        result.destination == SearchDestination.eventDetail
            ? result.destination
            : SearchDestination.unavailable,
      SearchResultType.jobs =>
        result.destination == SearchDestination.jobDetail
            ? result.destination
            : SearchDestination.unavailable,
    };
  }
}
