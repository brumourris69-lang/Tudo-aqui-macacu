import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/local_network_isolation.dart';
import '../../../core/config/local_search_environment.dart';
import '../../../features/tourism/models/tourist_spot.dart';
import '../../../features/news/models/public_news_article.dart';
import '../../../features/events/models/public_event.dart';
import '../../../features/jobs/models/public_job.dart';
import '../models/search_result.dart';
import '../policies/business_search_policy.dart';
import 'universal_search_repository.dart';

/// Callable protocol for the isolated Android demo only. The unsigned App Check
/// fixture is accepted ONLY by Functions Emulator; it is not real attestation.
class LocalUniversalSearchRepository implements UniversalSearchRepository {
  static Future<void> verifyIsolation() async {
    LocalSearchEnvironment.requireDemo(LocalSearchEnvironment.project);
    final native = await LocalNetworkIsolation.channel
        .invokeMapMethod<String, dynamic>('environment');
    if (native?['local'] != true ||
        native?['isolated'] != true ||
        LocalSearchEnvironment.host != '127.0.0.1') {
      throw StateError('Busca disponível somente na variante local isolada.');
    }
    LocalSearchEnvironment.requireDemo(
      FirebaseAuth.instance.app.options.projectId,
    );
  }

  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) async {
    final result = await invokeLocal('searchBusinesses', {
      'query': request.terms.join(' '),
      'filter': request.filter.name,
      'limit': request.limit,
      if (request.cursor != null)
        'cursor': {
          'queryKey': request.cursor!.queryKey,
          'lastIndexId': request.cursor!.lastIndexId,
        },
    });
    return decodeLocalSearchPage(result, request);
  }

  /// Shared isolated callable transport; never usable by a production variant.
  static Future<dynamic> invokeLocal(
    String function,
    Map<String, dynamic> data,
  ) async {
    if (!const {
      'searchBusinesses',
      'getSearchTourismSpot',
      'getSearchNewsArticle',
      'getSearchEvent',
      'getSearchJob',
      'getPublicJob',
      'listPublicContent',
      'getPublicContentDetail',
      'submitUserOperation',
    }.contains(function)) {
      throw ArgumentError('Callable local inválido.');
    }
    await verifyIsolation();
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('Sessão de teste indisponível.');
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final fixture =
        '${encode({'alg': 'none'})}.'
        '${encode({'sub': 'demo-local-app', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300})}.';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final call = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:5007/demo-universal-search/southamerica-east1/$function',
        ),
      );
      call.headers.contentType = ContentType.json;
      call.headers.set('Authorization', 'Bearer $token');
      call.headers.set('X-Firebase-AppCheck', fixture);
      call.write(jsonEncode({'data': data}));
      final response = await call.close().timeout(const Duration(seconds: 15));
      final body =
          jsonDecode(
                await utf8.decoder
                    .bind(response)
                    .join()
                    .timeout(const Duration(seconds: 15)),
              )
              as Map<String, dynamic>;
      if (response.statusCode != 200 || body['error'] != null) {
        throw StateError(
          'Não foi possível pesquisar. Tente novamente em instantes.',
        );
      }
      return body['result'];
    } finally {
      client.close(force: true);
    }
  }

  static Future<TouristSpot?> resolveTouristSpot(String id) async {
    if (id.trim().isEmpty || id.contains('/')) {
      throw const FormatException('Local turístico inválido.');
    }
    final value = await invokeLocal('getSearchTourismSpot', {'id': id});
    if (value == null) return null;
    if (value is! Map || value['id'] != id || value['data'] is! Map) {
      throw const FormatException('Resposta turística inválida.');
    }
    return TouristSpot.fromData(
      id,
      Map<String, dynamic>.from(value['data'] as Map),
    );
  }

  static Future<PublicNewsArticle?> resolveNewsArticle(String id) async {
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw const FormatException('Notícia inválida.');
    }
    final value = await invokeLocal('getSearchNewsArticle', {'id': id});
    if (value is! Map ||
        (value['status'] != 'available' && value['status'] != 'unavailable')) {
      throw const FormatException('Resposta de notícia inválida.');
    }
    if (value['status'] == 'unavailable') return null;
    if (value['id'] != id || value['data'] is! Map) {
      throw const FormatException('Resposta de notícia inválida.');
    }
    return PublicNewsArticle.fromMap({
      ...Map<String, dynamic>.from(value['data'] as Map),
      'id': id,
    });
  }

  static Future<PublicEvent?> resolveEvent(String id) async {
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw const FormatException('Evento inválido.');
    }
    final value = await invokeLocal('getSearchEvent', {'id': id});
    if (value is! Map ||
        (value['status'] != 'available' && value['status'] != 'unavailable')) {
      throw const FormatException('Resposta de evento inválida.');
    }
    if (value['status'] == 'unavailable') return null;
    if (value['id'] != id || value['data'] is! Map) {
      throw const FormatException('Resposta de evento inválida.');
    }
    return PublicEvent.fromMap({
      ...Map<String, dynamic>.from(value['data'] as Map),
      'id': id,
    });
  }

  static Future<PublicJob?> resolveJob(String id) async {
    return _resolveJobWith('getSearchJob', id);
  }

  /// Dedicated public detail contract, available only through the isolated
  /// demo transport. Production remains blocked by PublicJobDetailsRepository.
  static Future<PublicJob?> resolvePublicJob(String id) async {
    return _resolveJobWith('getPublicJob', id);
  }

  static Future<PublicJob?> _resolveJobWith(String callable, String id) async {
    PublicJob.validateId(id);
    final value = await invokeLocal(callable, {'id': id});
    return PublicJob.fromSearchResponse(value, requestedId: id);
  }
}

BusinessSearchPage decodeLocalSearchPage(
  dynamic value,
  BusinessSearchRequest request,
) {
  if (value is! Map ||
      value['results'] is! List ||
      (value['results'] as List).length > request.limit) {
    throw const FormatException('Resposta de pesquisa inválida.');
  }
  final results = (value['results'] as List).map((raw) {
    if (raw is! Map || raw['id'] is! String) {
      throw const FormatException('Destino de pesquisa inválido.');
    }
    final decoded = SearchResult.fromMap(raw);
    final allowed = switch (request.filter) {
      BusinessSearchFilter.all => {
        SearchResultType.establishment,
        SearchResultType.tourism,
        SearchResultType.news,
        SearchResultType.events,
        SearchResultType.jobs,
      }.contains(decoded.type),
      BusinessSearchFilter.tourism => decoded.type == SearchResultType.tourism,
      BusinessSearchFilter.news => decoded.type == SearchResultType.news,
      BusinessSearchFilter.events => decoded.type == SearchResultType.events,
      BusinessSearchFilter.jobs => decoded.type == SearchResultType.jobs,
      BusinessSearchFilter.commerce || BusinessSearchFilter.services =>
        decoded.type == SearchResultType.establishment,
    };
    if (!allowed) {
      throw const FormatException('Tipo incompatível com o filtro.');
    }
    return SearchResult.fromMap({
      ...decoded.toMap(),
      'imageUrl':
          isLocalEmulatorEndpoint(Uri.tryParse(decoded.imageUrl) ?? Uri())
          ? decoded.imageUrl
          : '',
    });
  }).toList();
  final cursor = value['nextCursor'];
  bool validCursorForFilter(String id) {
    final collectionPrefix = switch (request.filter) {
      BusinessSearchFilter.all => [
        'establishments__',
        'routes__',
        'news__',
        'events__',
        'jobs__',
      ],
      BusinessSearchFilter.tourism => ['routes__'],
      BusinessSearchFilter.news => ['news__'],
      BusinessSearchFilter.events => ['events__'],
      BusinessSearchFilter.jobs => ['jobs__'],
      BusinessSearchFilter.commerce ||
      BusinessSearchFilter.services => ['establishments__'],
    };
    for (final prefix in collectionPrefix) {
      if (id.startsWith(prefix)) {
        final originalId = id.substring(prefix.length);
        return originalId.isNotEmpty &&
            originalId.trim() == originalId &&
            !originalId.contains('/') &&
            originalId != '.' &&
            originalId != '..';
      }
    }
    return false;
  }

  if (cursor != null &&
      (cursor is! Map ||
          cursor.length != 2 ||
          cursor['queryKey'] != request.queryKey ||
          cursor['lastIndexId'] is! String ||
          !validCursorForFilter(cursor['lastIndexId'] as String))) {
    throw const FormatException('Cursor de pesquisa inválido.');
  }
  return BusinessSearchPage(
    results,
    cursor == null
        ? null
        : BusinessSearchCursor(
            cursor['queryKey'] as String,
            cursor['lastIndexId'] as String,
          ),
  );
}
