import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _RouteReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _RouteDocument implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _RouteDocument(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  DocumentReference<Map<String, dynamic>> get reference => _RouteReference();
  @override
  Map<String, dynamic> data() => Map.of(_data);
  @override
  bool get exists => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _RouteSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _RouteSnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Admin hub oferece entrada única para Explorar Macacu', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AdminContentHub()));

    expect(find.text('Explorar Macacu'), findsOneWidget);
    expect(find.text('Turismo e roteiros'), findsNothing);
  });

  testWidgets(
    'gerenciador de turismo lista drafts e oferece ordenação por arrastar',
    (tester) async {
      final snapshot = _RouteSnapshot([
        _RouteDocument('second', {
          'title': 'Trilha cadastrada',
          'category': 'trilhas',
          'order': 2,
          'published': true,
          'active': true,
        }),
        _RouteDocument('first', {
          'title': 'Ponto em rascunho',
          'category': 'pontos_turisticos',
          'order': 1,
          'published': false,
          'active': true,
        }),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ContentManager(
            collection: 'routes',
            title: 'Explorar Macacu',
            itemsStreamFactory: () => Stream.value(snapshot),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.text('Trilha cadastrada'), findsOneWidget);
      expect(find.text('Ponto em rascunho'), findsOneWidget);
      expect(find.byTooltip('Editar Ponto em rascunho'), findsOneWidget);
      expect(find.byTooltip('Editar Trilha cadastrada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
