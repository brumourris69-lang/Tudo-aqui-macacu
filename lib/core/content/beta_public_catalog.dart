import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../config/beta_environment.dart';
import 'premium_projection_result.dart';

/// Client-side reader for the deliberately curated, read-only Beta catalog.
/// It never reads the canonical administrative collections.
class BetaPublicCatalog {
  BetaPublicCatalog(this._firestore);

  static const pageSize = 40;
  static const maxUnboundedResults = 400;

  @visibleForTesting
  static String storageCollectionNameFor(String collection) {
    if (!collections.contains(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    return collection == 'establishments' ? 'establishments_basic' : collection;
  }

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
    'businessId': 128,
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
  static const _basicEstablishmentFields = <String>{
    'name',
    'title',
    'address',
    'location',
    'phone',
    'category',
    'subcategory',
    'order',
  };

  @visibleForTesting
  static bool containsOnlyBasicEstablishmentFields(Map<String, dynamic> data) =>
      data.keys.every(_basicEstablishmentFields.contains);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String collection) {
    _requireReady(collection);
    return _firestore
        .collection('beta_public_catalog')
        .doc(storageCollectionNameFor(collection))
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
        documents.add((
          id: document.id,
          data: _decode(document, collection: collection),
        ));
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
    return _decodeData(raw, collection: collection);
  }

  /// Reads one Premium projection by the canonical establishment ID. Firestore
  /// Rules validate the entitlement against server time and current canonical
  /// publication state; server-only reads avoid displaying cached entitlement.
  Future<PremiumProjectionResult> getPremiumEstablishment(String id) async {
    _requireReady('establishments');
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      return const PremiumProjectionResult(
        status: PremiumProjectionStatus.invalid,
      );
    }
    try {
      final snapshot = await _firestore
          .collection('beta_public_catalog')
          .doc('establishments_premium')
          .collection('items')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists) {
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.missing,
        );
      }
      final raw = snapshot.data();
      if (raw == null || !_validPremiumEnvelope(raw, expectedId: id)) {
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.invalid,
        );
      }
      return decodePremiumEstablishmentEnvelope(
        raw,
        expectedId: id,
        now: DateTime.now().toUtc(),
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.permissionDenied,
        );
      }
      if (const {
        'unavailable',
        'deadline-exceeded',
        'cancelled',
        'aborted',
        'resource-exhausted',
      }.contains(error.code)) {
        return const PremiumProjectionResult(
          status: PremiumProjectionStatus.unavailable,
        );
      }
      rethrow;
    }
  }

  @visibleForTesting
  static PremiumProjectionResult decodePremiumEstablishmentEnvelope(
    Map<String, dynamic> raw, {
    required String expectedId,
    required DateTime now,
  }) {
    if (!_validPremiumEnvelope(raw, expectedId: expectedId)) {
      return const PremiumProjectionResult(
        status: PremiumProjectionStatus.invalid,
      );
    }
    final expiry = (raw['premiumUntil'] as Timestamp).toDate().toUtc();
    if (!expiry.isAfter(now.toUtc())) {
      return const PremiumProjectionResult(
        status: PremiumProjectionStatus.expired,
      );
    }
    return PremiumProjectionResult.available(
      premiumUntil: expiry,
      data: Map<String, dynamic>.from(raw['publicData'] as Map),
    );
  }

  static bool _validPremiumEnvelope(
    Map<String, dynamic> raw, {
    required String expectedId,
  }) {
    if (raw.keys.toSet().difference(const {
          'visibility',
          'sourceId',
          'schemaVersion',
          'updatedAt',
          'listingTier',
          'premiumUntil',
          'publicData',
        }).isNotEmpty ||
        !raw.keys.toSet().containsAll(const {
          'visibility',
          'sourceId',
          'schemaVersion',
          'updatedAt',
          'listingTier',
          'premiumUntil',
          'publicData',
        }) ||
        raw['visibility'] != 'public' ||
        raw['sourceId'] != expectedId ||
        raw['schemaVersion'] != 1 ||
        raw['listingTier'] != 'premium' ||
        raw['updatedAt'] is! Timestamp ||
        raw['premiumUntil'] is! Timestamp ||
        raw['publicData'] is! Map) {
      return false;
    }
    final source = raw['publicData'] as Map;
    if (source.keys.any((key) => key is! String) ||
        source.keys.toSet().difference(const {
          'description',
          'shortDescription',
          'iconKey',
          'imageUrl',
          'logoUrl',
          'maps',
          'mapsUrl',
          'whatsapp',
          'instagram',
          'type',
          'contactUrl',
          'link',
          'hours',
          'additionalInfo',
          'galleryUrls',
          'videoUrls',
          'services',
          'products',
          'artwork',
          'featured',
          'open',
          'options',
        }).isNotEmpty) {
      return false;
    }
    for (final entry in source.entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (_textLimits.containsKey(key)) {
        if (value is! String || value.length > _textLimits[key]!) return false;
      } else if (_listFields.contains(key)) {
        final maxLength = key == 'services' || key == 'products' ? 40 : 20;
        if (value is! List ||
            value.length > maxLength ||
            value.any((item) => item is! String || item.length > 2048)) {
          return false;
        }
      } else if (_numberFields.contains(key)) {
        if (value is! int || value < 0 || value > 100000) return false;
      } else if (_boolFields.contains(key)) {
        if (value is! bool) return false;
      } else {
        return false;
      }
    }
    try {
      if (utf8.encode(jsonEncode(source)).length > 48 * 1024) return false;
    } on Object {
      return false;
    }
    return true;
  }

  Map<String, dynamic> _decode(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    required String collection,
  }) {
    final raw = document.data();
    if (raw['sourceId'] != document.id) {
      throw const FormatException('Documento público inválido.');
    }
    return _decodeData(raw, collection: collection);
  }

  Map<String, dynamic> _decodeData(
    Map<String, dynamic> raw, {
    required String collection,
  }) {
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
    if (collection == 'establishments' &&
        !containsOnlyBasicEstablishmentFields(data)) {
      throw const FormatException(
        'A projeção Básica contém campos comerciais não permitidos.',
      );
    }
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
