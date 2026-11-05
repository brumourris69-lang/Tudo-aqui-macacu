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
  testWidgets(
    'Admin content rows distinguish draft, public and removed states',
    (tester) async {
      final documents = [
        _AdminDoc('draft', {
          'name': 'Rascunho de teste',
          'published': false,
          'active': true,
        }),
        _AdminDoc('public', {
          'name': 'Publicado de teste',
          'published': true,
          'active': true,
        }),
        _AdminDoc('inactive', {
          'name': 'Inativo de teste',
          'published': true,
          'active': false,
        }),
        _AdminDoc('deleted', {
          'name': 'Excluído de teste',
          'published': false,
          'deleted': true,
        }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ContentManager(
            collection: 'establishments',
            title: 'Estabelecimentos',
            itemsStreamFactory: () => Stream.value(_AdminSnapshot(documents)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Rascunho'), findsOneWidget);
      expect(find.byTooltip('Publicado'), findsNWidgets(2));
      expect(find.byTooltip('Removido logicamente'), findsOneWidget);
      expect(find.text('Rascunho · Ativo'), findsOneWidget);
      expect(find.text('Publicado · Inativo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admin opens an establishment editor directly from its list', (
    tester,
  ) async {
    final document = _AdminDoc('mercado-serra', {
      'name': 'Mercado da Serra',
      'category': 'Comércio',
      'published': true,
      'active': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ContentManager(
          collection: 'establishments',
          title: 'Estabelecimentos',
          itemsStreamFactory: () => Stream.value(_AdminSnapshot([document])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar Mercado da Serra'));
    await tester.pumpAndSettle();

    expect(find.text('Editar estabelecimento'), findsOneWidget);
    expect(find.byTooltip('Pré-visualizar perfil'), findsOneWidget);
  });

  testWidgets(
    'Admin establishments search name location and shows active state',
    (tester) async {
      final docs = [
        _AdminDoc('a', {
          'name': 'Mercado Azul',
          'location': 'Centro',
          'active': false,
        }),
        _AdminDoc('b', {
          'name': 'Oficina Macacu',
          'location': 'Papucaia',
          'active': true,
        }),
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
      await tester.enterText(
        find.byKey(const ValueKey('establishment-admin-search')),
        'Papucaia',
      );
      await tester.pumpAndSettle();
      expect(find.text('Oficina Macacu'), findsOneWidget);
      expect(find.text('Mercado Azul'), findsNothing);
    },
  );

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
              _AdminSnapshot([
                _AdminDoc('a', {'name': 'Resultado após retry'}),
              ]),
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
        _AdminSnapshot([
          _AdminDoc('a', {'name': 'Novo estabelecimento'}),
        ]),
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
    expect(
      find.text('Ainda não há itens. Use Adicionar para publicar.'),
      findsOneWidget,
    );

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

  testWidgets('Admin can filter storefronts by publication and active state', (
    tester,
  ) async {
    final docs = [
      _AdminDoc('published', {
        'name': 'Mercado publicado',
        'published': true,
        'active': true,
      }),
      _AdminDoc('draft', {
        'name': 'Vitrine em rascunho',
        'published': false,
        'active': true,
      }),
      _AdminDoc('inactive', {
        'name': 'Loja pausada',
        'published': true,
        'active': false,
      }),
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

    expect(find.text('Mercado publicado'), findsOneWidget);
    expect(find.text('Vitrine em rascunho'), findsOneWidget);
    expect(find.text('Loja pausada'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('establishment-filter-published')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mercado publicado'), findsOneWidget);
    expect(find.text('Loja pausada'), findsOneWidget);
    expect(find.text('Vitrine em rascunho'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('establishment-filter-drafts')));
    await tester.pumpAndSettle();
    expect(find.text('Vitrine em rascunho'), findsOneWidget);
    expect(find.text('Mercado publicado'), findsNothing);
    expect(find.text('Loja pausada'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('establishment-filter-inactive')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loja pausada'), findsOneWidget);
    expect(find.text('Vitrine em rascunho'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('establishment-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('Mercado publicado'), findsOneWidget);
    expect(find.text('Vitrine em rascunho'), findsOneWidget);
    expect(find.text('Loja pausada'), findsOneWidget);
  });

  testWidgets(
    'advertisement manager caps creation at ten but keeps items editable',
    (tester) async {
      final docs = [
        for (var index = 1; index <= 10; index++)
          _AdminDoc('ad-$index', {'title': 'Campanha $index', 'order': index}),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ContentManager(
            collection: 'ads',
            title: 'Anúncios',
            itemsStreamFactory: () => Stream.value(_AdminSnapshot(docs)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('10 de 10 anúncios'), findsOneWidget);
      final addButton = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(addButton.onPressed, isNull);
      for (var index = 1; index <= 10; index++) {
        final editButton = find.byTooltip('Editar Campanha $index');
        await tester.scrollUntilVisible(
          editButton,
          240,
          scrollable: find.byType(Scrollable).last,
        );
        expect(editButton, findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
