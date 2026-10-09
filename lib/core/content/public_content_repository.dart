import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  FirebaseFirestore? firestore,
}) {
  final db = firestore ?? FirebaseFirestore.instance;
  // Backend revalidates visibility; no unrestricted Firestore listener.
  // Polling is cancellable, serialized and has no shared authorization cache.
  late StreamController<PublicContentSnapshot> controller;
  Timer? timer;
  var stopped = false;
  Future<void> refresh() async {
    try {
      final result = await getPublicContent(collection, firestore: db);
      if (!stopped) controller.add(result);
    } catch (error, stack) {
      if (!stopped) controller.addError(error, stack);
    }
    if (!stopped) timer = Timer(const Duration(seconds: 30), refresh);
  }

  controller = StreamController<PublicContentSnapshot>(
    onListen: refresh,
    onCancel: () {
      stopped = true;
      timer?.cancel();
    },
  );
  return controller.stream;
}
