import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config/local_network_isolation.dart';
import '../../../core/config/local_search_environment.dart';
import '../models/search_result.dart';
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
      'listPublicContent',
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
    if (raw is! Map ||
        raw['sourceCollection'] != 'establishments' ||
        raw['type'] != 'establishment' ||
        raw['destination'] != 'businessProfile' ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        (raw['id'] as String).contains('/')) {
      throw const FormatException('Destino de pesquisa inválido.');
    }
    String text(String key) => raw[key] is String ? raw[key] as String : '';
    final image = text('imageUrl');
    return SearchResult(
      id: text('id'),
      sourceCollection: 'establishments',
      title: text('title'),
      summary: text('summary'),
      category: text('category'),
      subcategory: text('subcategory'),
      type: SearchResultType.establishment,
      destination: SearchDestination.businessProfile,
      imageUrl: isLocalEmulatorEndpoint(Uri.tryParse(image) ?? Uri())
          ? image
          : '',
    );
  }).toList();
  final cursor = value['nextCursor'];
  if (cursor != null &&
      (cursor is! Map ||
          cursor['queryKey'] != request.queryKey ||
          cursor['lastIndexId'] is! String ||
          !(cursor['lastIndexId'] as String).startsWith('establishments__') ||
          (cursor['lastIndexId'] as String).contains('/'))) {
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
