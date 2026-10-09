import '../models/search_result.dart';
import '../policies/business_search_policy.dart';
import '../utils/search_normalization.dart';

class BusinessSearchRequest {
  BusinessSearchRequest({
    required String query,
    this.filter = BusinessSearchFilter.all,
    this.limit = 20,
    this.cursor,
  }) : terms = prepareSearchTerms(query) {
    if (query.length > 80 ||
        terms.isEmpty ||
        terms.length > 4 ||
        terms.any((term) => term.length < 2 || term.length > 24) ||
        limit < 1 ||
        limit > 20) {
      throw ArgumentError(
        'Use 1–4 palavras de 2–24 caracteres e limite de 1–20.',
      );
    }
    if (cursor != null && cursor!.queryKey != queryKey) {
      throw ArgumentError('Cursor pertence a outra pesquisa.');
    }
  }
  final List<String> terms;
  final BusinessSearchFilter filter;
  final int limit;
  final BusinessSearchCursor? cursor;
  String get queryKey => '${filter.name}:${(terms.toList()..sort()).join(' ')}';
  String get anchor =>
      (terms.toList()..sort((a, b) {
            final length = b.length.compareTo(a.length);
            return length != 0 ? length : a.compareTo(b);
          }))
          .first;
}

/// Transport adapter must validate this value; it is not an authorization token.
class BusinessSearchCursor {
  const BusinessSearchCursor(this.queryKey, this.lastIndexId);
  final String queryKey, lastIndexId;
}

class BusinessSearchPage {
  BusinessSearchPage(Iterable<SearchResult> results, this.nextCursor)
    : results = List.unmodifiable(results);
  final List<SearchResult> results;
  final BusinessSearchCursor? nextCursor;
}

abstract interface class UniversalSearchRepository {
  Future<BusinessSearchPage> search(BusinessSearchRequest request);
}
