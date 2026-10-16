import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _AdminDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _AdminDoc(this.id, this.fields);
  @override
  final String id;
  final Map<String, dynamic> fields;
  @override
  Map<String, dynamic> data() => fields;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _AdminSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _AdminSnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Admin establishments search name location and shows active state', (
    tester,
  ) async {
    final docs = [
      _AdminDoc('a', {'name': 'Mercado Azul', 'location': 'Centro', 'active': false}),
      _AdminDoc('b', {'name': 'Oficina Macacu', 'location': 'Papucaia', 'active': true}),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ContentManager(
          collection: 'establishments',
          title: 'Estabelecimentos',
          itemsStreamFactory: () => Stream.value(_AdminSnapshot(docs)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Publicado · Inativo'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('establishment-admin-search')), 'Papucaia');
    await tester.pumpAndSettle();
    expect(find.text('Oficina Macacu'), findsOneWidget);
    expect(find.text('Mercado Azul'), findsNothing);
  });

  testWidgets('Admin establishments list retries after an initial error', (
    tester,
  ) async {
    final failed = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    var attempts = 0;
    Stream<QuerySnapshot<Map<String, dynamic>>> load() {
      attempts++;
      return attempts == 1
          ? failed.stream
          : Stream.value(
              _AdminSnapshot([_AdminDoc('a', {'name': 'Resultado após retry'})]),
            );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ContentManager(
          collection: 'establishments',
          title: 'Estabelecimentos',
          itemsStreamFactory: load,
        ),
      ),
    );
    await tester.pump();
    failed.addError(StateError('offline'));
    await tester.pump();
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Resultado após retry'), findsOneWidget);
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox());
    unawaited(failed.close());
  });

  testWidgets('Admin empty result still offers retry after refresh failure', (
    tester,
  ) async {
    final updates = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    var attempts = 0;
    Stream<QuerySnapshot<Map<String, dynamic>>> load() {
      attempts++;
      if (attempts == 1) return updates.stream;
      return Stream.value(
        _AdminSnapshot([_AdminDoc('a', {'name': 'Novo estabelecimento'})]),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ContentManager(
          collection: 'establishments',
          title: 'Estabelecimentos',
          itemsStreamFactory: load,
        ),
      ),
    );
    updates.add(_AdminSnapshot(const []));
    await tester.pump();
    expect(find.text('Ainda não há itens. Use Adicionar para publicar.'), findsOneWidget);

    updates.addError(StateError('offline'));
    await tester.pump();
    expect(find.text('Não foi possível atualizar os itens.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Novo estabelecimento'), findsOneWidget);
    expect(attempts, 2);

    await tester.pumpWidget(const SizedBox());
    unawaited(updates.close());
  });
}
