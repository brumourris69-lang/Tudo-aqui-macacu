import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/supabase_search_pilot_config.dart';
import '../../businesses/models/business.dart';
import '../models/search_result.dart';
import '../policies/business_search_policy.dart';
import 'universal_search_repository.dart';

enum SupabaseSearchPilotFailure { transport, timeout, server, malformed }

class SupabaseSearchPilotException implements Exception {
  const SupabaseSearchPilotException(this.failure, {this.statusCode});

  final SupabaseSearchPilotFailure failure;
  final int? statusCode;

  @override
  String toString() => 'SupabaseSearchPilotException($failure)';
}

/// Public establishment-only adapter. It has no Firebase repository fallback.
class SupabaseSearchPilotRepository implements UniversalSearchRepository {
  SupabaseSearchPilotRepository({
    required this.config,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const _maxResponseBytes = 64 * 1024;
  static const _searchKeys = {
    'id',
    'name',
    'summary',
    'category',
    'subcategory',
    'image_url',
    'has_more',
  };
  static const _detailKeys = {
    'id',
    'name',
    'summary',
    'category',
    'subcategory',
    'image_url',
  };
  static const _categories = {
    ...BusinessSearchPolicy.commerceCategories,
    ...BusinessSearchPolicy.serviceCategories,
  };
  static final _idPattern = RegExp(r'^pilot-[a-z0-9-]{1,60}$');

  final SupabaseSearchPilotConfig config;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<BusinessSearchPage> search(BusinessSearchRequest request) async {
    final category = switch (request.filter) {
      BusinessSearchFilter.all => 'all',
      BusinessSearchFilter.commerce => 'commerce',
      BusinessSearchFilter.services => 'services',
      _ => throw UnsupportedError('Filtro indisponível no piloto de busca.'),
    };
    final cursorId = request.cursor?.lastIndexId;
    String? lastId;
    if (cursorId != null) {
      const prefix = 'establishments__';
      if (!cursorId.startsWith(prefix)) {
        throw ArgumentError('Cursor inválido para estabelecimentos.');
      }
      lastId = cursorId.substring(prefix.length);
      if (!_idPattern.hasMatch(lastId)) {
        throw ArgumentError('Cursor inválido para estabelecimentos.');
      }
    }

    final payload = await _call('search_public_establishments', {
      'p_query': request.terms.join(' '),
      'p_category': category,
      'p_page_size': request.limit,
      'p_cursor_id': lastId,
    });
    if (payload is! List || payload.length > request.limit) {
      throw const FormatException('Resposta de busca inválida.');
    }

    final results = <SearchResult>[];
    final ids = <String>{};
    bool? hasMore;
    for (final value in payload) {
      final row = _object(value, _searchKeys);
      final rowHasMore = row['has_more'];
      if (rowHasMore is! bool || (hasMore != null && rowHasMore != hasMore)) {
        throw const FormatException('Resposta de busca inválida.');
      }
      hasMore = rowHasMore;
      final result = _searchResult(row);
      if (!ids.add(result.id)) {
        throw const FormatException('Resposta de busca inválida.');
      }
      results.add(result);
    }

    if (hasMore == true && results.isEmpty) {
      throw const FormatException('Resposta de busca inválida.');
    }
    return BusinessSearchPage(
      results,
      hasMore == true
          ? BusinessSearchCursor(
              request.queryKey,
              'establishments__${results.last.id}',
            )
          : null,
    );
  }

  Future<Business?> getPublicBusiness(String id) async {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError('Identificador de estabelecimento inválido.');
    }
    final payload = await _call('get_public_establishment', {'p_id': id});
    if (payload is! List || payload.length > 1) {
      throw const FormatException('Resposta de detalhe inválida.');
    }
    if (payload.isEmpty) return null;
    final row = _object(payload.single, _detailKeys);
    final result = _validatedPublicFields(row);
    if (result['id'] != id) {
      throw const FormatException('Resposta de detalhe inválida.');
    }
    return Business.fromData(id, {
      'name': result['name'],
      'shortDescription': result['summary'],
      'category': result['category'],
      'subcategory': result['subcategory'],
      'imageUrl': result['image_url'],
      'location': '',
    });
  }

  Future<Object?> _call(String rpc, Map<String, Object?> body) async {
    final request =
        http.Request('POST', config.url.replace(path: '/rest/v1/rpc/$rpc'))
          ..headers.addAll({
            'apikey': config.anonKey,
            'authorization': 'Bearer ${config.anonKey}',
            'content-type': 'application/json',
            'accept': 'application/json',
          })
          ..followRedirects = false
          ..body = jsonEncode(body);

    late final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.timeout,
      );
    } on SocketException {
      throw const SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.transport,
      );
    } on http.ClientException {
      throw const SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.transport,
      );
    } catch (_) {
      throw const SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.transport,
      );
    }

    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > _maxResponseBytes) {
      await response.stream.listen(null).cancel();
      throw const FormatException('Resposta Supabase excede o limite.');
    }
    final bytes = <int>[];
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > _maxResponseBytes) {
          throw const FormatException('Resposta Supabase excede o limite.');
        }
        bytes.addAll(chunk);
      }
    } on TimeoutException {
      throw const SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.timeout,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.transport,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSearchPilotException(
        SupabaseSearchPilotFailure.server,
        statusCode: response.statusCode,
      );
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('Resposta Supabase inválida.');
    }
  }

  SearchResult _searchResult(Map<String, Object?> row) {
    final fields = _validatedPublicFields(row);
    return SearchResult.fromMap({
      'id': fields['id'],
      'sourceCollection': 'establishments',
      'title': fields['name'],
      'summary': fields['summary'],
      'category': fields['category'],
      'subcategory': fields['subcategory'],
      'imageUrl': fields['image_url'],
      'type': 'establishment',
      'destination': 'businessProfile',
    });
  }

  Map<String, Object?> _validatedPublicFields(Map<String, Object?> row) {
    final id = row['id'];
    final name = row['name'];
    final summary = row['summary'];
    final category = row['category'];
    final subcategory = row['subcategory'];
    final imageUrl = row['image_url'];
    if (id is! String ||
        !_idPattern.hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 100 ||
        summary is! String ||
        summary.length > 500 ||
        category is! String ||
        !_categories.contains(category) ||
        subcategory is! String ||
        subcategory.length > 80 ||
        imageUrl is! String ||
        !_validImageUrl(imageUrl)) {
      throw const FormatException('Campos públicos inválidos.');
    }
    return {
      'id': id,
      'name': name,
      'summary': summary,
      'category': category,
      'subcategory': subcategory,
      'image_url': imageUrl,
    };
  }

  bool _validImageUrl(String value) {
    if (value.isEmpty) return true;
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasPort;
  }

  Map<String, Object?> _object(Object? value, Set<String> allowedKeys) {
    if (value is! Map) {
      throw const FormatException('Resposta Supabase inválida.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String || !allowedKeys.contains(entry.key)) {
        throw const FormatException(
          'Resposta Supabase contém campo não aprovado.',
        );
      }
      result[entry.key as String] = entry.value;
    }
    if (!result.keys.toSet().containsAll(
          allowedKeys.where((key) => key != 'has_more'),
        ) ||
        (allowedKeys.contains('has_more') && !result.containsKey('has_more'))) {
      throw const FormatException('Resposta Supabase incompleta.');
    }
    return result;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
