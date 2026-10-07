import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const _a = 'https://example.com/a.jpg';
const _b = 'https://example.com/b.jpg';
const _c = 'https://example.com/c.jpg';

// Offline document double for the actual editor.
// ignore: subtype_of_sealed_class
class _Document implements DocumentSnapshot<Map<String, dynamic>> {
  _Document(this.reference, this.fields);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> fields;
  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(fields);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Model only Firestore's top-level update/delete contract, intercepting the
// actual write before audit/navigation. A replacement set is not supported.
// ignore: subtype_of_sealed_class
class _Reference implements DocumentReference<Map<String, dynamic>> {
  _Reference(Map<String, dynamic> initial)
    : stored = Map<String, dynamic>.from(initial);
  final Map<String, dynamic> stored;
  final List<Map<String, dynamic>> writes = [];
  @override
  Future<void> update(Map<Object, Object?> data) async {
    final patch = Map<String, dynamic>.from(data);
    writes.add(patch);
    for (final entry in patch.entries) {
      if (entry.value == FieldValue.delete()) {
        stored.remove(entry.key);
      } else {
        stored[entry.key] = entry.value;
      }
    }
    throw FirebaseException(plugin: 'test', code: 'intercepted-write');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<dynamic> _mount(
  WidgetTester tester, {
  _Reference? reference,
  Map<String, dynamic>? initial,
  String collection = 'events',
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 5000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ContentEditor(
        collection: collection,
        doc: reference == null ? null : _Document(reference, initial!),
      ),
    ),
  );
  return tester.state(find.byType(ContentEditor));
}

Map<String, dynamic> _initial() => {
  'title': 'Evento',
  'description': 'Descrição antiga',
  'imageUrl': _a,
  'galleryUrls': [_a, _b, _c],
  'legacyField': 'preservar',
  'metadata': {
    'source': 'import',
    'extra': ['original'],
  },
};

Future<void> _save(WidgetTester tester, dynamic editor) async {
  await editor.save();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

ContentMediaGalleryEditor _gallery(WidgetTester tester) => tester
    .widget<ContentMediaGalleryEditor>(find.byType(ContentMediaGalleryEditor));

void main() {
  testWidgets('Tecnologia is selectable for new and existing businesses', (
    tester,
  ) async {
    for (final editing in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      final initial = <String, dynamic>{
        'title': 'Fixture',
        'category': 'Tecnologia',
        'subcategory': 'Provedores de internet',
        'imageUrl': '',
      };
      final dynamic editor = await _mount(
        tester,
        reference: editing ? _Reference(initial) : null,
        initial: editing ? initial : null,
        collection: 'establishments',
      );
      final selector = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .first;
      final dropdown = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .first;
      expect(dropdown.items!.any((item) => item.value == 'Tecnologia'), isTrue);
      if (editing) {
        expect(editor.category.text, 'Tecnologia');
        expect(editor.subcategory.text, 'Provedores de internet');
      }
      selector.onChanged!('Tecnologia');
      await tester.pump();
      final data = editor.prepareSaveData() as Map<String, dynamic>;
      expect(data['category'], 'Tecnologia');
      expect(data['artwork'], 18);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'ad editor preserves media and link and saves order and activation',
    (tester) async {
      final initial = <String, dynamic>{
        'title': 'Campanha',
        'imageUrl': '',
        'link': 'https://example.com',
        'order': 12,
        'active': false,
        'legacyField': 'preservar',
      };
      final ref = _Reference(initial);
      final dynamic editor = await _mount(
        tester,
        reference: ref,
        initial: initial,
        collection: 'ads',
      );
      expect(editor.bannerOrder.text, '12');
      expect(editor.bannerActive, isFalse);
      editor.bannerOrder.text = '3';
      editor.bannerActive = true;
      await _save(tester, editor);
      expect(ref.stored['order'], 3);
      expect(ref.stored['active'], isTrue);
      expect(ref.stored['link'], initial['link']);
      expect(ref.stored['imageUrl'], initial['imageUrl']);
      expect(ref.stored['legacyField'], 'preservar');
    },
  );
  testWidgets('editing preserves unknown fields and concurrent extra values', (
    tester,
  ) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    ref.stored['concurrentExtra'] = 'written after editor opened';
    editor.description.text = 'Nova descrição';
    await _save(tester, editor);
    expect(ref.stored['legacyField'], 'preservar');
    expect(ref.stored['concurrentExtra'], 'written after editor opened');
    expect(ref.writes.single.containsKey('legacyField'), isFalse);
  });

  testWidgets('editing preserves an unknown nested map intact', (tester) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.description.text = 'Nova descrição';
    await _save(tester, editor);
    expect(ref.stored['metadata'], initial['metadata']);
    expect(ref.writes.single.containsKey('metadata'), isFalse);
  });

  testWidgets('known fields replace their previous values', (tester) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.description.text = 'Nova descrição';
    editor.published = false;
    await _save(tester, editor);
    expect(ref.stored['description'], 'Nova descrição');
    expect(ref.stored['published'], false);
  });

  testWidgets('clearing a known text field does not restore its old value', (
    tester,
  ) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.description.clear();
    await _save(tester, editor);
    expect(ref.stored['description'], '');
  });

  testWidgets('removed gallery image does not return after saving', (
    tester,
  ) async {
    final initial = _initial();
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    _gallery(tester).onRemove(1);
    await tester.pump();
    await _save(tester, editor);
    expect(ref.stored['galleryUrls'], [_a, _c]);
    expect(ref.stored['imageUrl'], _a);
  });

  testWidgets('gallery changes preserve legacy fields and alternate media', (
    tester,
  ) async {
    final initial = _initial()..['images'] = ['legacy media'];
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    _gallery(tester).onCover(2);
    await tester.pump();
    _gallery(tester).onRemove(1);
    await tester.pump();
    await _save(tester, editor);
    expect(ref.stored['galleryUrls'], [_c, _b]);
    expect(ref.stored['imageUrl'], _c);
    expect(ref.stored['legacyField'], 'preservar');
    expect(ref.stored['images'], ['legacy media']);
  });

  testWidgets(
    'new document prepares the same creation fields without deletes',
    (tester) async {
      final dynamic editor = await _mount(tester);
      editor.title.text = 'Novo evento';
      editor.description.text = 'Descrição';
      final data = Map<String, dynamic>.from(editor.prepareSaveData());
      expect(data.keys.toSet(), {
        'title',
        'description',
        'link',
        'imageUrl',
        'artwork',
        'galleryUrls',
        'category',
        'location',
        'address',
        'eventDate',
        'date',
        'contact',
        'whatsapp',
        'phone',
        'instagram',
        'maps',
        'additionalInfo',
        'published',
        'updatedAt',
      });
      expect(data['title'], 'Novo evento');
      expect(data['description'], 'Descrição');
      expect(data['galleryUrls'], isEmpty);
      expect(data['published'], true);
      expect(data['updatedAt'], FieldValue.serverTimestamp());
      expect(data.values, isNot(contains(FieldValue.delete())));
    },
  );

  testWidgets('clearing expiry intentionally deletes the existing expiry', (
    tester,
  ) async {
    final initial = _initial()
      ..['expiresAt'] = Timestamp.fromDate(DateTime(2030, 1, 1));
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    editor.expires.clear();
    await _save(tester, editor);
    expect(ref.stored.containsKey('expiresAt'), isFalse);
    expect(ref.writes.single['expiresAt'], FieldValue.delete());
  });

  testWidgets('timestamps and publication extras remain outside the patch', (
    tester,
  ) async {
    final initial = _initial()
      ..addAll({
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'publishedAt': Timestamp.fromDate(DateTime(2021)),
        'active': false,
        'status': 'approved',
        'order': 40,
      });
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
    );
    final currentCreatedAt = Timestamp.fromDate(DateTime(2019));
    ref.stored['createdAt'] = currentCreatedAt;
    await _save(tester, editor);
    expect(ref.stored['createdAt'], currentCreatedAt);
    for (final key in ['publishedAt', 'active', 'status', 'order']) {
      expect(ref.stored[key], initial[key]);
      expect(ref.writes.single.containsKey(key), isFalse);
    }
    expect(ref.writes.single['updatedAt'], FieldValue.serverTimestamp());
    expect(ref.writes.single.containsKey('createdAt'), isFalse);
  });

  testWidgets('business logo and complete gallery can still be cleared', (
    tester,
  ) async {
    final initial = _initial()..['logoUrl'] = 'https://example.com/logo.jpg';
    final ref = _Reference(initial);
    final dynamic editor = await _mount(
      tester,
      reference: ref,
      initial: initial,
      collection: 'establishments',
    );
    editor.logoUrl.clear();
    for (var i = 0; i < 3; i++) {
      _gallery(tester).onRemove(0);
      await tester.pump();
    }
    await _save(tester, editor);
    expect(ref.stored['logoUrl'], '');
    expect(ref.stored['imageUrl'], '');
    expect(ref.stored['galleryUrls'], isEmpty);
    expect(ref.stored['legacyField'], 'preservar');
  });
}
