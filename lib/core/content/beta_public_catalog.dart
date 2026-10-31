import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/beta_environment.dart';

/// Client-side reader for the deliberately curated, read-only Beta catalog.
/// It never reads the canonical administrative collections.
class BetaPublicCatalog {
  BetaPublicCatalog(this._firestore);

  static const pageSize = 40;
  static const maxUnboundedResults = 400;

  static const collections = <String>{
    'establishments',
    'ads',
    'offers',
    'coupons',
    'alerts',
    'routes',
    'polls',
    'jobs',
    'news',
    'events',
    'links',
    'utilities',
    'health',
    'transport',
    'trash_collection',
    'useful_phones',
    'pharmacy_duties',
    'emergency_contacts',
    'resolver_subjects',
    'public_places',
  };

  static const _textLimits = <String, int>{
    'name': 160,
    'title': 160,
    'category': 100,
    'subcategory': 100,
    'description': 4000,
    'shortDescription': 1000,
    'location': 500,
    'address': 500,
    'iconKey': 80,
    'imageUrl': 2048,
    'logoUrl': 2048,
    'maps': 2048,
    'mapsUrl': 2048,
    'phone': 80,
    'whatsapp': 160,
    'instagram': 300,
    'type': 100,
    'employmentType': 100,
    'company': 200,
    'eventDate': 100,
    'endDate': 100,
    'date': 100,
    'startsAt': 100,
    'startTime': 40,
    'endTime': 40,
    'organizer': 200,
    'registrationUrl': 2048,
    'contactUrl': 2048,
    'link': 2048,
    'destinationType': 80,
    'destination': 2048,
    'promotionTitle': 200,
    'promotionDescription': 1000,
    'hours': 500,
    'additionalInfo': 2000,
  };

  static const _listFields = <String>{
    'galleryUrls',
    'videoUrls',
    'services',
    'products',
    'options',
  };

  static const _numberFields = <String>{'artwork', 'order'};
  static const _boolFields = <String>{'featured', 'open'};
  static const _dateFields = <String>{
    'eventDate',
    'endDate',
    'date',
    'startsAt',
  };

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String collection) {
    _requireReady(collection);
    return _firestore
        .collection('beta_public_catalog')
        .doc(collection)
        .collection('items');
  }

  void _requireReady(String collection) {
    if (!collections.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    BetaEnvironment.requireReady();
    BetaEnvironment.requireFirebaseProject(_firestore.app.options.projectId);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _page(
    String collection, {
    required int size,
    String? after,
  }) {
    Query<Map<String, dynamic>> query = _items(collection)
        .where('visibility', isEqualTo: 'public')
        .orderBy(FieldPath.documentId)
        .limit(size);
    if (after != null) query = query.startAfter([after]);
    return query
        .get(const GetOptions(source: Source.server))
        .then((snapshot) => snapshot.docs);
  }

  Future<List<({String id, Map<String, dynamic> data})>> list(
    String collection, {
    int? limit,
  }) async {
    _requireReady(collection);
    if (limit != null && (limit < 1 || limit > maxUnboundedResults)) {
      throw RangeError.range(limit, 1, maxUnboundedResults, 'limit');
    }

    final target = limit ?? maxUnboundedResults;
    final documents = <({String id, Map<String, dynamic> data})>[];
    String? cursor;
    while (documents.length < target) {
      final remaining = target - documents.length;
      final size = remaining < pageSize ? remaining : pageSize;
      final page = await _page(collection, size: size, after: cursor);
      for (final document in page) {
        documents.add((id: document.id, data: _decode(document)));
      }
      if (page.length < size) return documents;
      cursor = page.last.id;
      if (limit != null && documents.length >= limit) return documents;
    }

    // Detect truncation instead of silently presenting an incomplete catalog.
    if (limit == null &&
        (await _page(collection, size: 1, after: cursor)).isNotEmpty) {
      throw StateError(
        'Catálogo excede o limite de leitura desta versão Beta.',
      );
    }
    return documents;
  }

  Future<Map<String, dynamic>?> get({
    required String collection,
    required String id,
  }) async {
    _requireReady(collection);
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw const FormatException('Conteúdo inválido.');
    }
    final matches = await _items(collection)
        .where('visibility', isEqualTo: 'public')
        .where(FieldPath.documentId, isEqualTo: id)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (matches.docs.isEmpty) return null;
    final raw = matches.docs.single.data();
    if (raw['sourceId'] != id) {
      throw const FormatException('Documento público inválido.');
    }
    return _decodeData(raw);
  }

  Map<String, dynamic> _decode(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final raw = document.data();
    if (raw['sourceId'] != document.id) {
      throw const FormatException('Documento público inválido.');
    }
    return _decodeData(raw);
  }

  Map<String, dynamic> _decodeData(Map<String, dynamic> raw) {
    if (raw.keys.toSet().difference(const {
          'visibility',
          'sourceId',
          'schemaVersion',
          'updatedAt',
          'publicData',
        }).isNotEmpty ||
        raw['visibility'] != 'public' ||
        raw['schemaVersion'] != 1 ||
        !raw.keys.toSet().containsAll(const {
          'visibility',
          'sourceId',
          'schemaVersion',
          'updatedAt',
          'publicData',
        }) ||
        raw['updatedAt'] is! Timestamp ||
        raw['publicData'] is! Map) {
      throw const FormatException('Documento público inválido.');
    }

    final source = raw['publicData'] as Map;
    if (source.keys.any((key) => key is! String)) {
      throw const FormatException('Projeção pública inválida.');
    }
    final data = Map<String, dynamic>.from(source);
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (_textLimits.containsKey(key)) {
        final validDate = _dateFields.contains(key) && value is Timestamp;
        if ((!validDate && value is! String) ||
            (value is String && value.length > _textLimits[key]!)) {
          throw const FormatException('Campo da projeção pública inválido.');
        }
      } else if (_listFields.contains(key)) {
        if (value is! List ||
            value.length > 20 ||
            value.any((item) => item is! String || item.length > 2048)) {
          throw const FormatException('Lista da projeção pública inválida.');
        }
      } else if (_numberFields.contains(key)) {
        if (value is! int || value < 0 || value > 100000) {
          throw const FormatException('Número da projeção pública inválido.');
        }
      } else if (_boolFields.contains(key)) {
        if (value is! bool) {
          throw const FormatException('Estado da projeção pública inválido.');
        }
      } else {
        throw const FormatException('Campo não permitido na projeção pública.');
      }
      if (_dateFields.contains(key) &&
          value is! String &&
          value is! Timestamp) {
        throw const FormatException('Data da projeção pública inválida.');
      }
    }
    if ((data['name'] ?? data['title']) is! String ||
        (data['name'] ?? data['title']).toString().trim().isEmpty) {
      throw const FormatException('Conteúdo público sem título.');
    }

    final byteLength = utf8
        .encode(
          jsonEncode(
            data,
            toEncodable: (value) {
              if (value is Timestamp) return value.toDate().toIso8601String();
              return value.toString();
            },
          ),
        )
        .length;
    if (byteLength > 48 * 1024) {
      throw const FormatException(
        'Projeção pública excede o limite permitido.',
      );
    }

    // Publication is represented by the curated projection itself. The source
    // status and private administrative fields are never copied to the client.
    return {...data, 'published': true, 'active': true};
  }
}
