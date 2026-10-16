import '../models/search_result.dart';
import '../policies/business_search_policy.dart';
import '../utils/search_normalization.dart';

bool _validIndexCursor(String value) {
  for (final prefix in [
    'establishments__',
    'routes__',
    'news__',
    'events__',
    'jobs__',
  ]) {
    if (value.startsWith(prefix)) {
      final id = value.substring(prefix.length);
      return id.isNotEmpty &&
          id.trim() == id &&
          !id.contains('/') &&
          id != '.' &&
          id != '..';
    }
  }
  return false;
}

class SearchQueryValidationException extends ArgumentError {
  SearchQueryValidationException() : super(description);
  static const description =
      'Use de 1 a 4 palavras, cada uma com 2 a 24 caracteres, e no máximo 80 caracteres no total.';
}

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
        terms.any((term) => term.length < 2 || term.length > 24)) {
      throw SearchQueryValidationException();
    }
    if (limit < 1 || limit > 20) {
      throw ArgumentError('Limite de 1–20 resultados.');
    }
    if (cursor != null &&
        (cursor!.queryKey != queryKey ||
            !_validIndexCursor(cursor!.lastIndexId) ||
            (filter == BusinessSearchFilter.tourism &&
                !cursor!.lastIndexId.startsWith('routes__')) ||
            (filter == BusinessSearchFilter.news &&
                !cursor!.lastIndexId.startsWith('news__')) ||
            (filter == BusinessSearchFilter.events &&
                !cursor!.lastIndexId.startsWith('events__')) ||
            (filter == BusinessSearchFilter.jobs &&
                !cursor!.lastIndexId.startsWith('jobs__')) ||
            (filter != BusinessSearchFilter.all &&
                filter != BusinessSearchFilter.tourism &&
                filter != BusinessSearchFilter.news &&
                filter != BusinessSearchFilter.events &&
                filter != BusinessSearchFilter.jobs &&
                !cursor!.lastIndexId.startsWith('establishments__')) ||
            (filter == BusinessSearchFilter.all &&
                ![
                  'establishments__',
                  'routes__',
                  'news__',
                  'events__',
                  'jobs__',
                ].any(cursor!.lastIndexId.startsWith)))) {
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
