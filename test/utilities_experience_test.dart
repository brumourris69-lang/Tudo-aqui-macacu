import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

// ignore: subtype_of_sealed_class
class _EmptyUtilitySnapshot
    implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _UtilityDocument implements DocumentSnapshot<Map<String, dynamic>> {
  _UtilityDocument(this.fields);

  final Map<String, dynamic> fields;

  @override
  Map<String, dynamic> data() => fields;

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

    expect(find.text('Informações e orientações importantes para atendimento'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
          (widget) => widget is TextField &&
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
}
