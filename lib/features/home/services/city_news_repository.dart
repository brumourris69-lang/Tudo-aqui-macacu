import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../../core/config/spark_public_catalog_environment.dart';
import '../models/city_news_item.dart';

class CityNewsSnapshot {
  const CityNewsSnapshot({
    required this.source,
    required this.profileUrl,
    required this.posts,
  });

  final String source;
  final Uri profileUrl;
  final List<CityNewsItem> posts;
}

abstract interface class CityNewsRepository {
  bool get isAvailable;
  Future<CityNewsSnapshot> load({bool forceRefresh = false});
}

class PrefeituraRssNewsRepository implements CityNewsRepository {
  PrefeituraRssNewsRepository({
    String endpoint = const String.fromEnvironment(
      'CITY_NEWS_FEED_ENDPOINT',
      defaultValue:
          'https://tudo-aqui-macacu-image-upload.tudo-aqui-macacu-image-upload.workers.dev/v1/city-news',
    ),
    http.Client? client,
    bool Function()? distributionReady,
  }) : _endpoint = endpoint,
       _client = client ?? http.Client(),
       _distributionReady =
           distributionReady ?? (() => SparkPublicCatalogEnvironment.ready);

  final String _endpoint;
  final http.Client _client;
  final bool Function() _distributionReady;
  CityNewsSnapshot? _cached;
  DateTime? _expiresAt;

  static const _ttl = Duration(minutes: 5);
  static const _source = 'Prefeitura de Cachoeiras de Macacu';
  static const _sourceUrl = 'https://www.prefeituracachoeiras.com/noticias';

  @override
  bool get isAvailable =>
      _distributionReady() && _validEndpoint(Uri.tryParse(_endpoint));

  @override
  Future<CityNewsSnapshot> load({bool forceRefresh = false}) async {
    if (!isAvailable) throw StateError('Feed municipal não configurado.');
    final now = DateTime.now();
    if (!forceRefresh &&
        _cached != null &&
        _expiresAt != null &&
        now.isBefore(_expiresAt!)) {
      return _cached!;
    }
    final response = await _client
        .get(
          Uri.parse(_endpoint),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('Notícias da Prefeitura indisponíveis.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map ||
        decoded['source'] != _source ||
        decoded['profileUrl'] != _sourceUrl ||
        decoded['posts'] is! List) {
      throw const FormatException('Resposta do feed municipal inválida.');
    }
    final posts = (decoded['posts'] as List)
        .map(CityNewsItem.tryParse)
        .whereType<CityNewsItem>()
        .take(10)
        .toList(growable: false);
    final snapshot = CityNewsSnapshot(
      source: _source,
      profileUrl: Uri.parse(_sourceUrl),
      posts: posts,
    );
    _cached = snapshot;
    _expiresAt = now.add(_ttl);
    return snapshot;
  }

  static bool _validEndpoint(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.host ==
          'tudo-aqui-macacu-image-upload.tudo-aqui-macacu-image-upload.workers.dev' &&
      uri.path == '/v1/city-news' &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  @visibleForTesting
  static bool endpointIsAllowed(String value) =>
      _validEndpoint(Uri.tryParse(value));
}
