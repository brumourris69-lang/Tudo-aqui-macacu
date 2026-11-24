import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/beta_environment.dart';
import '../config/spark_public_catalog_environment.dart';
import 'beta_public_catalog.dart';
import 'secure_backend.dart';

/// Public data envelope, deliberately not a fabricated Firestore snapshot.
class PublicContentDocument {
  PublicContentDocument(this.id, this._data, this.reference);
  final String id;
  final Map<String, dynamic> _data;
  final DocumentReference<Map<String, dynamic>> reference;
  Map<String, dynamic> data() => Map.of(_data);
}

class PublicContentSnapshot {
  PublicContentSnapshot(this.docs);
  final List<PublicContentDocument> docs;
  factory PublicContentSnapshot.fromFirestore(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => PublicContentSnapshot(
    snapshot.docs
        .map((doc) => PublicContentDocument(doc.id, doc.data(), doc.reference))
        .toList(),
  );
}

dynamic decodePublicValue(dynamic value) {
  if (value is Map && value.length == 1 && value['_publicTimestamp'] is List) {
    final parts = value['_publicTimestamp'] as List;
    if (parts.length != 2 || parts.any((v) => v is! int)) {
      throw const FormatException('Data pública inválida.');
    }
    return Timestamp(parts[0] as int, parts[1] as int);
  }
  if (value is List) {
    return value.map(decodePublicValue).toList();
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), decodePublicValue(item)),
    );
  }
  return value;
}

Future<PublicContentSnapshot> getPublicContent(
  String collection, {
  int? limit,
  FirebaseFirestore? firestore,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  if (SparkPublicCatalogEnvironment.usesProjectionReads(
    betaBuild: BetaEnvironment.enabled,
  )) {
    if (BetaEnvironment.enabled) {
      BetaEnvironment.requireReady();
      BetaEnvironment.requireFirebaseProject(db.app.options.projectId);
    } else {
      SparkPublicCatalogEnvironment.requireReady(
        actualProjectId: db.app.options.projectId,
      );
    }
    final projected = await BetaPublicCatalog(
      db,
    ).list(collection, limit: limit);
    return PublicContentSnapshot(
      projected
          .map(
            (item) => PublicContentDocument(
              item.id,
              item.data,
              db
                  .collection('beta_public_catalog')
                  .doc(BetaPublicCatalog.storageCollectionNameFor(collection))
                  .collection('items')
                  .doc(item.id),
            ),
          )
          .toList(growable: false),
    );
  }
  final docs = <PublicContentDocument>[];
  String? cursor;
  // Preserve existing full-list views via bounded pages. Fail explicitly rather
  // than silently truncate on the local safety cap; no unbounded collection read.
  for (var page = 0; page < 10; page++) {
    final remaining = limit == null ? 40 : (limit - docs.length).clamp(1, 40);
    final result = await SecureBackend.invoke('listPublicContent', {
      'collection': collection,
      'limit': remaining,
      'cursor': ?cursor,
    });
    if (result is! Map ||
        result['items'] is! List ||
        (result['items'] as List).length > remaining) {
      throw const FormatException('Resposta pública inválida.');
    }
    for (final item in result['items'] as List) {
      if (item is! Map ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          (item['id'] as String).contains('/') ||
          item['data'] is! Map) {
        throw const FormatException('Documento público inválido.');
      }
      final id = item['id'] as String;
      docs.add(
        PublicContentDocument(
          id,
          Map<String, dynamic>.from(decodePublicValue(item['data']) as Map),
          db.collection(collection).doc(id),
        ),
      );
    }
    final next = result['nextCursor'];
    if (next == null || (limit != null && docs.length >= limit)) {
      return PublicContentSnapshot(docs);
    }
    if (next is! String ||
        next == cursor ||
        next.isEmpty ||
        next.contains('/')) {
      throw const FormatException('Página pública inválida.');
    }
    cursor = next;
  }
  throw StateError(
    'Listagem local excedeu o limite de páginas. Refine a seleção.',
  );
}

Stream<PublicContentSnapshot> watchPublicContent(
  String collection, {
  int? limit,
  FirebaseFirestore? firestore,
}) {
  final db = firestore ?? FirebaseFirestore.instance;
  return _publicContentFeedCache.watch(
    source: db,
    key: '$collection:${limit ?? 'all'}',
    load: () => getPublicContent(collection, limit: limit, firestore: db),
  );
}

/// Replays recent public data immediately, then refreshes it in the background.
/// Cache entries are memory-only and scoped to the Firestore instance, so Beta,
/// local emulators, and distribution cannot share data with one another.
class PublicContentFeedCache {
  PublicContentFeedCache({
    this.cacheDuration = const Duration(minutes: 2),
    this.refreshInterval = const Duration(seconds: 30),
  });

  final Duration cacheDuration;
  final Duration refreshInterval;
  final Expando<Map<String, _PublicContentCacheEntry>> _entries = Expando(
    'public content cache by Firebase instance',
  );

  Stream<PublicContentSnapshot> watch({
    required Object source,
    required String key,
    required Future<PublicContentSnapshot> Function() load,
  }) {
    late StreamController<PublicContentSnapshot> controller;
    Timer? timer;
    var stopped = false;
    var loading = false;
    final entries = _entries[source] ??= <String, _PublicContentCacheEntry>{};

    Future<void> refresh() async {
      if (stopped || loading) return;
      loading = true;
      try {
        final result = await load();
        entries[key] = _PublicContentCacheEntry(result, DateTime.now());
        if (!stopped) controller.add(result);
      } catch (error, stack) {
        if (!stopped) controller.addError(error, stack);
      } finally {
        loading = false;
        if (!stopped) timer = Timer(refreshInterval, refresh);
      }
    }

    controller = StreamController<PublicContentSnapshot>(
      onListen: () {
        final cached = entries[key];
        if (cached != null &&
            DateTime.now().difference(cached.updatedAt) <= cacheDuration) {
          controller.add(cached.snapshot);
        }
        unawaited(refresh());
      },
      onCancel: () {
        stopped = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }
}

class _PublicContentCacheEntry {
  const _PublicContentCacheEntry(this.snapshot, this.updatedAt);

  final PublicContentSnapshot snapshot;
  final DateTime updatedAt;
}

final PublicContentFeedCache _publicContentFeedCache = PublicContentFeedCache();
