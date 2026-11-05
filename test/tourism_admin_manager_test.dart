import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
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

    await _scrollToText(tester, 'Explorar Macacu');
    expect(find.text('Explorar Macacu'), findsOneWidget);
    expect(find.text('Turismo e roteiros'), findsNothing);
  });

  testWidgets(
    'Admin content hub groups existing modules without dropping entries',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AdminContentHub()),
      );

      for (final label in [
        'Eventos e divulgação',
        'Eventos',
        'Banners e campanhas',
        'Cupons',
        'Notícias',
        'Enquetes',
        'Turismo e história',
        'Explorar Macacu',
        'Serviços da cidade',
        'Utilidades da cidade',
        'Ônibus',
        'Coleta',
        'Telefones úteis',
        'Alertas da cidade',
        'Emergência',
        'Onde Resolver?',
        'Locais públicos',
        'Saúde',
        'Trabalho',
        'Vagas',
      ]) {
        await _scrollToText(tester, label);
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'Módulo preservado: $label',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Admin content search matches names without accents and clears', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AdminContentHub()),
    );

    final search = find.byKey(const ValueKey('admin-content-search'));
    await tester.enterText(search, 'TELEFONES UTEIS');
    await tester.pumpAndSettle();
    expect(find.text('Telefones úteis'), findsOneWidget);
    expect(find.text('Trabalho'), findsNothing);
    expect(find.text('Vagas'), findsNothing);

    await tester.enterText(search, 'ONIB');
    await tester.pumpAndSettle();
    expect(find.text('Ônibus'), findsOneWidget);
    expect(find.text('Telefones úteis'), findsNothing);

    await tester.enterText(search, 'emergencia');
    await tester.pumpAndSettle();
    expect(find.text('Emergência'), findsOneWidget);
    expect(find.text('Telefones úteis'), findsNothing);

    await tester.enterText(search, 'modulo inexistente');
    await tester.pumpAndSettle();
    expect(find.text('Nenhum módulo encontrado'), findsOneWidget);
    expect(find.text('Tente outro nome ou limpe a busca.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-content-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum módulo encontrado'), findsNothing);
    await _scrollToText(tester, 'Trabalho');
    expect(find.text('Vagas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin module search keeps existing utility destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminContentHub(
          utilitiesStreamFactory: () => Stream.value(
            _RouteSnapshot(
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('admin-content-search')),
      'utilidades',
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    await tester.tap(find.text('Utilidades da cidade'));
    await tester.pumpAndSettle();

    expect(find.byType(UtilityManager), findsOneWidget);
    expect(find.text('Utilidades da cidade'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin categories stay usable on narrow and enlarged layouts', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.5]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const AdminContentHub(),
          ),
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('admin-content-search')),
          'emergencia',
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Emergência'),
          findsOneWidget,
          reason: 'busca em largura ${width.toInt()}, escala $scale',
        );
        await tester.tap(
          find.byKey(const ValueKey('admin-content-search-clear')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'largura ${width.toInt()}, escala $scale',
        );
      }
    }
  });

  testWidgets('Administration tools remain grouped and available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AdminSettingsHub()),
    );

    for (final label in [
      'Ferramentas de conteúdo',
      'Acompanhamento',
      'Atendimento',
      'Importar conteúdo inicial',
      'Notificações',
      'Métricas',
      'Histórico administrativo',
      'Avaliações e correções',
      'Mensagens recebidas',
    ]) {
      await _scrollToText(tester, label);
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
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

Future<void> _scrollToText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  fail('Não encontrou "$label" ao percorrer o painel.');
}
