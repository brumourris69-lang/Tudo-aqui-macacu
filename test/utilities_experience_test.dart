import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _EmptyUtilitySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _UtilityDocument implements DocumentSnapshot<Map<String, dynamic>> {
  _UtilityDocument(
    this.fields, {
    this.id = 'utility-test',
    _UtilityReference? reference,
  }) : _reference = reference ?? _UtilityReference(id, fields);

  final Map<String, dynamic> fields;
  final _UtilityReference _reference;
  @override
  final String id;

  @override
  Map<String, dynamic> data() => fields;

  @override
  DocumentReference<Map<String, dynamic>> get reference => _reference;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _UtilityReference implements DocumentReference<Map<String, dynamic>> {
  _UtilityReference(this.id, this.fields);

  @override
  final String id;
  final Map<String, dynamic> fields;
  final List<int> deleteCalls = [];

  @override
  Future<void> delete() {
    deleteCalls.add(1);
    return Future<void>.error(
      FirebaseException(plugin: 'cloud_firestore', code: 'test-denied'),
    );
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    fields.addAll(data.cast<String, dynamic>());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _UtilityQueryDocument
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _UtilityQueryDocument(this.id, this.fields);

  @override
  final String id;
  final Map<String, dynamic> fields;

  @override
  Map<String, dynamic> data() => fields;

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      _UtilityReference(id, fields);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UtilitySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _UtilitySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ResourcesHub distinguishes loading and published utilities', (
    tester,
  ) async {
    final controller = StreamController<List<UtilityItem>>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: ResourcesHub(utilitiesStreamFactory: () => controller.stream),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.add([
      const UtilityItem(
        id: 'water',
        name: 'Conta de água',
        iconKey: 'water',
        description: 'Avisos publicados',
        destinationType: 'internal',
        destination: 'water',
        order: 10,
      ),
      const UtilityItem(
        id: 'disabled',
        name: 'Atalho desativado',
        iconKey: 'services',
        description: '',
        destinationType: 'internal',
        destination: 'cityHall',
        order: 20,
        active: false,
      ),
      const UtilityItem(
        id: 'city-hall',
        name: 'Prefeitura',
        iconKey: 'cityHall',
        description: 'Canais publicados',
        destinationType: 'internal',
        destination: 'cityHall',
        order: 30,
        category: 'Serviços públicos',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Conta de Água e Energia'), findsOneWidget);
    expect(find.text('Serviços públicos'), findsOneWidget);
    expect(find.text('Prefeitura'), findsOneWidget);
    expect(find.text('Atalho desativado'), findsNothing);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Buscar uma utilidade...',
      ),
      'Serviços públicos',
    );
    await tester.pumpAndSettle();
    expect(find.text('Prefeitura'), findsOneWidget);
    expect(find.text('Conta de Água e Energia'), findsNothing);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Buscar uma utilidade...',
      ),
      'não existe',
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma utilidade encontrada.'), findsOneWidget);
  });

  testWidgets('ResourcesHub reports failures and retries its source', (
    tester,
  ) async {
    var subscriptions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ResourcesHub(
          utilitiesStreamFactory: () {
            subscriptions++;
            return subscriptions == 1
                ? Stream<List<UtilityItem>>.error(StateError('offline'))
                : Stream<List<UtilityItem>>.value(const []);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar as utilidades.'),
      findsOneWidget,
    );
    expect(find.text('Ônibus'), findsNothing);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(subscriptions, 2);
    expect(find.text('Ônibus'), findsOneWidget);
  });

  testWidgets('ResourcesHub keeps long utility cards within narrow tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = StreamController<List<UtilityItem>>();
    addTearDown(controller.close);
    late double receivedTextScale;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 900),
            textScaler: TextScaler.linear(1.7),
          ),
          child: Builder(
            builder: (context) {
              receivedTextScale = MediaQuery.textScalerOf(context).scale(1);
              return ResourcesHub(
                utilitiesStreamFactory: () => controller.stream,
              );
            },
          ),
        ),
      ),
    );
    expect(receivedTextScale, 1.7);
    controller.add([
      const UtilityItem(
        id: 'long-entry',
        name: 'Informações e orientações importantes para atendimento',
        iconKey: 'services',
        description:
            'Consulte instruções detalhadas e informações adicionais antes de iniciar.',
        destinationType: 'internal',
        destination: 'cityHall',
        order: 1,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(
      find.text('Informações e orientações importantes para atendimento'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'utility names remain fully readable across phone widths and text scales',
    (tester) async {
      const name = 'Conta de Água e Energia para atendimento municipal';
      const item = UtilityItem(
        id: 'water-energy',
        name: name,
        iconKey: 'waterEnergy',
        description: 'Informações e avisos sobre água e energia.',
        destinationType: 'internal',
        destination: 'transport',
        order: 10,
      );

      for (final width in [320.0, 360.0, 393.0, 480.0]) {
        for (final scale in [1.0, 1.7]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: TextScaler.linear(scale),
                ),
                child: ResourcesHub(
                  utilitiesStreamFactory: () => Stream.value(const [item]),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final title = tester.renderObject<RenderParagraph>(find.text(name));
          expect(
            title.didExceedMaxLines,
            isFalse,
            reason: '$width dp at scale $scale',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$width dp at scale $scale',
          );
        }
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'UtilityInfoPage reports a read error instead of spinning forever',
    (tester) async {
      var subscriptions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UtilityInfoPage(
            title: 'Transporte',
            subtitle: 'Linhas cadastradas',
            collection: 'transport',
            searchHint: 'Buscar linha...',
            empty: 'Nenhuma linha.',
            icon: Icons.directions_bus,
            utilitiesStreamFactory: (_) {
              subscriptions++;
              return subscriptions == 1
                  ? Stream<List<Map<String, dynamic>>>.error(
                      StateError('offline'),
                    )
                  : Stream<List<Map<String, dynamic>>>.value([
                      {'title': 'Linha Centro'},
                    ]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar as informações.'),
        findsOneWidget,
      );
      expect(find.text('Nenhuma linha.'), findsNothing);
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(subscriptions, 2);
      expect(find.text('Linha Centro'), findsOneWidget);
    },
  );

  testWidgets('UtilityInfoPage shows its empty state after a successful read', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UtilityInfoPage(
          title: 'Transporte',
          subtitle: 'Linhas cadastradas',
          collection: 'transport',
          searchHint: 'Buscar linha...',
          empty: 'Nenhuma linha.',
          icon: Icons.directions_bus,
          utilitiesStreamFactory: (_) =>
              Stream<List<Map<String, dynamic>>>.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma linha.'), findsOneWidget);
  });

  testWidgets('UtilityEditor explains why an incomplete entry cannot save', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: UtilityEditor()));
    await tester.scrollUntilVisible(
      find.text('Salvar utilidade'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Salvar utilidade'));
    await tester.pump();

    expect(find.text('Informe o nome da utilidade.'), findsOneWidget);
  });

  testWidgets('UtilityEditor adapts destination input to selected type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const cases = [
      (
        type: 'url',
        label: 'Endereço HTTPS',
        keyboard: TextInputType.url,
        helper: 'HTTPS',
      ),
      (
        type: 'phone',
        label: 'Telefone',
        keyboard: TextInputType.phone,
        helper: 'DDD',
      ),
      (
        type: 'whatsapp',
        label: 'Telefone ou link wa.me',
        keyboard: TextInputType.text,
        helper: 'wa.me',
      ),
      (
        type: 'map',
        label: 'URL HTTPS ou URI geo',
        keyboard: TextInputType.url,
        helper: 'geo',
      ),
    ];

    for (final destinationCase in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: UtilityEditor(
            key: ValueKey(destinationCase.type),
            doc: _UtilityDocument({'destinationType': destinationCase.type}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final destinationField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == destinationCase.label,
        ),
      );
      expect(destinationField.keyboardType, destinationCase.keyboard);
      expect(
        destinationField.decoration?.helperText,
        contains(destinationCase.helper),
      );
    }
  });

  testWidgets('UtilityManager reports read failures and retries', (
    tester,
  ) async {
    var subscriptions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UtilityManager(
          streamFactory: () {
            subscriptions++;
            return subscriptions == 1
                ? Stream<QuerySnapshot<Map<String, dynamic>>>.error(
                    StateError('offline'),
                  )
                : Stream<QuerySnapshot<Map<String, dynamic>>>.value(
                    _EmptyUtilitySnapshot(),
                  );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar as utilidades.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(subscriptions, 2);
    expect(find.text('Não foi possível carregar as utilidades.'), findsNothing);
    expect(
      find.text(
        'Ainda não há utilidades cadastradas. Use Adicionar para criar a primeira.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'UtilityManager reorders without duplicate or negative positions',
    (tester) async {
      final documents = [
        _UtilityQueryDocument('a-bus', {
          'name': 'Ônibus',
          'destinationType': 'internal',
          'destination': 'transport',
          'order': 10,
        }),
        _UtilityQueryDocument('b-trash', {
          'name': 'Coleta de lixo',
          'destinationType': 'internal',
          'destination': 'trash',
          'order': 20,
        }),
        _UtilityQueryDocument('c-health', {
          'name': 'Saúde',
          'destinationType': 'internal',
          'destination': 'health',
          'order': 30,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: UtilityManager(
            streamFactory: () => Stream.value(
              _UtilitySnapshot(
                documents.cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
              ),
            ),
            reorderHandler: (items) async {
              final documentsById = {
                for (final document in documents) document.id: document,
              };
              for (final item in items) {
                documentsById[item.id]!.fields['order'] = item.order;
              }
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstUp = find.ancestor(
        of: find.byTooltip('Subir').first,
        matching: find.byType(IconButton),
      );
      final lastDown = find.ancestor(
        of: find.byTooltip('Descer').last,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(firstUp.first).onPressed, isNull);
      expect(tester.widget<IconButton>(lastDown.first).onPressed, isNull);
      await tester.tap(find.byTooltip('Subir').last);
      await tester.pumpAndSettle();

      final ordered = [...documents]
        ..sort(
          (a, b) =>
              (a.fields['order'] as int).compareTo(b.fields['order'] as int),
        );
      expect(ordered.map((doc) => doc.id), ['a-bus', 'c-health', 'b-trash']);
      final positions = documents
          .map((doc) => doc.fields['order'] as int)
          .toList();
      expect(positions.every((position) => position > 0), isTrue);
      expect(positions.toSet().length, positions.length);
    },
  );

  testWidgets(
    'UtilityEditor asks before deleting and Cancel keeps the utility',
    (tester) async {
      final reference = _UtilityReference('bus', {'name': 'Ônibus'});
      final document = _UtilityDocument(
        reference.fields,
        id: 'bus',
        reference: reference,
      );
      await tester.pumpWidget(MaterialApp(home: UtilityEditor(doc: document)));
      await tester.scrollUntilVisible(
        find.text('Excluir utilidade'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Excluir utilidade'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Ônibus'), findsOneWidget);
      expect(reference.deleteCalls, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(reference.deleteCalls, isEmpty);

      await tester.scrollUntilVisible(
        find.text('Excluir utilidade'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Excluir utilidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir').last);
      await tester.pumpAndSettle();
      expect(reference.deleteCalls, hasLength(1));
    },
  );
}
