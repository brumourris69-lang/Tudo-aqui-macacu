import '../../../core/content/public_content_detail_repository.dart';
import '../../../core/content/secure_backend.dart';
import '../../businesses/models/business.dart';
import '../../businesses/repositories/business_repository.dart';
import '../../events/models/public_event.dart';
import '../../tourism/models/tourist_spot.dart';
import '../policies/business_search_policy.dart';
import 'local_universal_search_repository.dart';
import 'universal_search_repository.dart';

typedef BetaPublicSearchInvoker =
    Future<dynamic> Function(String operation, Map<String, dynamic> data);

/// Public catalog search for the isolated Beta flavor. Its only transport is
/// SecureBackend, which checks Beta identity/readiness and has no Firestore or
/// emulator fallback.
class BetaPublicSearchRepository implements UniversalSearchRepository {
  BetaPublicSearchRepository({BetaPublicSearchInvoker? invoke})
    : _invoke = invoke ?? SecureBackend.invoke;

  static const supportedFilters = <BusinessSearchFilter>{
    BusinessSearchFilter.all,
    BusinessSearchFilter.commerce,
    BusinessSearchFilter.services,
    BusinessSearchFilter.tourism,
    BusinessSearchFilter.events,
  };

  static const _publicSources = {'establishments', 'routes', 'events'};

  final BetaPublicSearchInvoker _invoke;

  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) async {
    if (!supportedFilters.contains(request.filter)) {
      throw ArgumentError('Filtro indisponível na busca pública Beta.');
    }
    final value = await _invoke('searchPublicContent', {
      'query': request.terms.join(' '),
      'filter': request.filter.name,
      'limit': request.limit,
      if (request.cursor != null)
        'cursor': {
          'queryKey': request.cursor!.queryKey,
          'lastIndexId': request.cursor!.lastIndexId,
        },
    });
    final page = decodeLocalSearchPage(value, request);
    if (page.results.any(
      (result) => !_publicSources.contains(result.sourceCollection),
    )) {
      throw const FormatException(
        'A busca retornou conteúdo fora do catálogo público.',
      );
    }
    return page;
  }

  static Future<Business?> resolveBusiness(String id) async {
    return BusinessRepository().getPublicBusiness(id);
  }

  static Future<TouristSpot?> resolveTourism(String id) async {
    final data = await PublicContentDetailRepository().resolve(
      collection: 'routes',
      id: id,
    );
    return data == null ? null : TouristSpot.fromData(id, data);
  }

  static Future<PublicEvent?> resolveEvent(String id) async {
    final data = await PublicContentDetailRepository().resolve(
      collection: 'events',
      id: id,
    );
    return data == null ? null : PublicEvent.fromMap({...data, 'id': id});
  }
}
