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
  _Document(this.reference, {this.fixture});

  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? fixture;

  @override
  Map<String, dynamic> data() =>
      fixture ??
      {
        'title': 'Local',
        'category': 'Pontos turísticos',
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
  Future<void> update(Map<Object, Object?> data) async {
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

Future<void> _mountGalleryAtWidth(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: ContentMediaGalleryEditor(
            urls: photos,
            input: TextEditingController(),
            onAdd: () {},
            onMove: (_, _) {},
            onReorder: (_, _) {},
            onCover: (_) {},
            onRemove: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('callback move B up preserves all photos', (tester) async {
    await _mountEditor(tester, _WriteBoundary());
    _gallery(tester).onMove(1, -1);
    await tester.pump();
    expect(_gallery(tester).urls, [photos[1], photos[0], photos[2]]);
  });

  testWidgets('editor places the stored cover first in the public gallery', (
    tester,
  ) async {
    final reference = _WriteBoundary();
    await tester.binding.setSurfaceSize(const Size(1000, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ContentEditor(
          collection: 'routes',
          doc: _Document(
            reference,
            fixture: {
              'title': 'Trilha',
              'category': 'Pontos turísticos',
              'imageUrl': photos[2],
              'galleryUrls': photos,
            },
          ),
        ),
      ),
    );

    expect(_gallery(tester).urls, [photos[2], photos[0], photos[1]]);
  });

  testWidgets('galeria permite reorganizar fotos com arrastar e soltar', (
    tester,
  ) async {
    await _mountEditor(tester, _WriteBoundary());

    expect(find.byType(ReorderableListView), findsOneWidget);
    final dragHandle = find.byKey(const ValueKey('gallery-drag-handle-0'));
    await tester.ensureVisible(dragHandle);
    await tester.drag(dragHandle, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(_gallery(tester).urls, [photos[1], photos[0], photos[2]]);
  });

  testWidgets('toque na miniatura abre prévia ampliada e pode fechar', (
    tester,
  ) async {
    await _mountEditor(tester, _WriteBoundary());

    await tester.tap(find.byKey(const ValueKey('gallery-preview-0')));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Fechar prévia'), findsOneWidget);
    expect(find.text('Não foi possível carregar esta foto.'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar prévia'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('galeria cabe em celular estreito sem overflow', (tester) async {
    await _mountGalleryAtWidth(tester, 320);

    expect(tester.takeException(), isNull);
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
