import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const photos = [
  'https://example.com/a.jpg',
  'https://example.com/b.jpg',
  'https://example.com/c.jpg',
];

// Test double for the editor document; never used with a Firebase backend.
// ignore: subtype_of_sealed_class
class _Document implements DocumentSnapshot<Map<String, dynamic>> {
  _Document(this.reference);

  @override
  final DocumentReference<Map<String, dynamic>> reference;

  @override
  Map<String, dynamic> data() => {
    'title': 'Local',
    'imageUrl': photos.first,
    'galleryUrls': photos,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Captures the real save payload without initializing Firebase.
// ignore: subtype_of_sealed_class
class _WriteBoundary implements DocumentReference<Map<String, dynamic>> {
  final writes = <Map<String, dynamic>>[];
  Map<String, dynamic>? get payload => writes.isEmpty ? null : writes.last;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    writes.add(Map<String, dynamic>.from(data));
    // Stop at the persistence boundary: no Firebase or audit service is called.
    throw FirebaseException(plugin: 'test', code: 'intercepted-write');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mountEditor(WidgetTester tester, _WriteBoundary reference) async {
  await tester.binding.setSurfaceSize(const Size(1000, 5000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ContentEditor(collection: 'routes', doc: _Document(reference)),
    ),
  );
}

ContentMediaGalleryEditor _gallery(WidgetTester tester) => tester
    .widget<ContentMediaGalleryEditor>(find.byType(ContentMediaGalleryEditor));

void main() {
  testWidgets('callback move B up preserves all photos', (tester) async {
    await _mountEditor(tester, _WriteBoundary());
    _gallery(tester).onMove(1, -1);
    await tester.pump();
    expect(_gallery(tester).urls, [photos[1], photos[0], photos[2]]);
  });

  testWidgets('callback move B down preserves all photos', (tester) async {
    await _mountEditor(tester, _WriteBoundary());
    _gallery(tester).onMove(1, 1);
    await tester.pump();
    expect(_gallery(tester).urls, [photos[0], photos[2], photos[1]]);
  });

  testWidgets('callback sets C as cover without losing A or B', (tester) async {
    await _mountEditor(tester, _WriteBoundary());
    _gallery(tester).onCover(2);
    await tester.pump();
    expect(_gallery(tester).urls, [photos[2], photos[0], photos[1]]);
  });

  testWidgets('callback removes only B', (tester) async {
    await _mountEditor(tester, _WriteBoundary());
    _gallery(tester).onRemove(1);
    await tester.pump();
    expect(_gallery(tester).urls, [photos[0], photos[2]]);
  });

  testWidgets('successive callbacks preserve the remaining photos', (
    tester,
  ) async {
    await _mountEditor(tester, _WriteBoundary());
    _gallery(tester).onMove(1, -1);
    await tester.pump();
    _gallery(tester).onCover(2);
    await tester.pump();
    _gallery(tester).onRemove(1);
    await tester.pump();
    expect(_gallery(tester).urls, [photos[2], photos[0]]);
  });

  testWidgets('save prepares exactly the gallery and cover after edits', (
    tester,
  ) async {
    final reference = _WriteBoundary();
    await _mountEditor(tester, reference);
    _gallery(tester).onMove(1, -1);
    await tester.pump();
    _gallery(tester).onCover(2);
    await tester.pump();
    _gallery(tester).onRemove(1);
    await tester.pump();

    final dynamic editor = tester.state(find.byType(ContentEditor));
    await editor.save();
    await tester.pump();
    expect(reference.payload?['galleryUrls'], [photos[2], photos[0]]);
    expect(reference.payload?['imageUrl'], photos[2]);
    expect(tester.takeException(), isNull);
  });
}
