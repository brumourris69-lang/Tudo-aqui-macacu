import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/admin_edit/admin_edit_session.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/home_title_edit_pilot.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

class _AdminUser implements User {
  @override
  bool get isAnonymous => false;
  @override
  String get email => adminEmail;
  @override
  String get displayName => 'Admin';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _original = 'O que você procura hoje?';
const _changed = 'Encontre em Macacu';

class _Fixture {
  final weather = unavailableWeather();
  final key = GlobalKey<HomeTitleEditPilotState>();
  final writes = <({String title, bool publish})>[];
  String published = _original;
  String? draft;
  int searches = 0;
  Future<void> Function()? beforeSave;

  Widget page({bool admin = true}) {
    final user = admin ? _AdminUser() : null;
    final config = HomePageConfig.fromMap({
      'heroTitle': published,
      'visual': {'backgroundType': 'gradient'},
    });
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomeTitleEditPilot(
            key: key,
            isAdmin: isAdminUser(user),
            publishedTitle: config.heroTitle,
            onSave: (title, publish) async {
              await beforeSave?.call();
              writes.add((title: title, publish: publish));
              draft = title;
              if (publish) published = title;
            },
            builder: (title, onEdit, onStart, active) => WelcomeHero(
              weatherService: weather,
              config: config,
              user: user,
              onSearch: () => searches++,
              titleOverride: title,
              onEditTitle: onEdit,
              onToggleEditMode: onStart,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _start(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(fixture.page());
  await tester.tap(find.byTooltip('Editar'));
  await tester.pumpAndSettle();
}

Future<void> _change(WidgetTester tester, [String value = _changed]) async {
  await tester.tap(find.text('Toque para editar'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), value);
  await tester.tap(find.text('Concluir'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'session requires authorization and clears all flags on authorization loss',
    () {
      final session = AdminEditSession();
      session.activate();
      session.togglePreview();
      session.setDirty(true);
      expect(session.active, false);
      expect(session.dirty, false);
      expect(session.preview, false);
      session.setAuthorized(true);
      session.activate();
      session.setDirty(true);
      session.togglePreview();
      expect(session.active && session.dirty && session.preview, true);
      session.setAuthorized(false);
      expect(session.active || session.dirty || session.preview, false);
      session.dispose();
    },
  );

  testWidgets('ordinary user has no entry or editable title', (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.page(admin: false));
    expect(find.byTooltip('Editar'), findsNothing);
    expect(find.text('Toque para editar'), findsNothing);
    await tester.tap(find.text(_original));
    await tester.pump();
    expect(find.byType(TextFormField), findsNothing);
    expect(fixture.key.currentState!.session.active, false);
    expect(fixture.writes, isEmpty);
  });

  testWidgets('admin has discreet entry but title is not initially editable', (
    tester,
  ) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.page());
    expect(find.byTooltip('Editar'), findsOneWidget);
    expect(find.text('Toque para editar'), findsNothing);
    expect(fixture.key.currentState!.session.active, false);
  });

  testWidgets('entry activates session and selects only the pilot title', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    expect(find.text('Editando Home'), findsOneWidget);
    expect(find.text('Toque para editar'), findsOneWidget);
    expect(fixture.key.currentState!.session.active, true);
    expect(find.text('Textos'), findsNothing);
    expect(find.text('Identidade visual'), findsNothing);
  });

  testWidgets(
    'conclude changes local title and dirty state without any writes',
    (tester) async {
      final fixture = _Fixture();
      await _start(tester, fixture);
      await _change(tester);
      expect(find.text(_changed), findsOneWidget);
      expect(find.text('Alterações não salvas'), findsOneWidget);
      expect(fixture.key.currentState!.session.dirty, true);
      expect(fixture.writes, isEmpty);
      expect(fixture.published, _original);
      expect(fixture.draft, isNull);
    },
  );

  testWidgets('cancel leaves title unchanged and does not mark dirty', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.tap(find.text('Toque para editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), _changed);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text(_original), findsOneWidget);
    expect(fixture.key.currentState!.session.dirty, false);
    expect(fixture.writes, isEmpty);
  });

  testWidgets(
    'preview hides controls, preserves local title and returns to editing',
    (tester) async {
      final fixture = _Fixture();
      await _start(tester, fixture);
      await _change(tester);
      await tester.tap(find.text('Visualizar como usuário'));
      await tester.pumpAndSettle();
      expect(find.text(_changed), findsOneWidget);
      expect(find.text('Toque para editar'), findsNothing);
      expect(find.text('Salvar rascunho'), findsNothing);
      expect(find.text('Publicar'), findsNothing);
      expect(find.byTooltip('Editar'), findsNothing);
      await tester.tap(find.text(_changed));
      await tester.pump();
      expect(find.byType(TextFormField), findsNothing);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.text('Voltar à edição'));
      await tester.pumpAndSettle();
      expect(find.text('Toque para editar'), findsOneWidget);
      expect(fixture.key.currentState!.session.dirty, true);
    },
  );

  testWidgets('discard restores published title and makes no writes', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text(_original), findsOneWidget);
    expect(fixture.key.currentState!.session.active, false);
    expect(fixture.writes, isEmpty);
  });

  testWidgets(
    'leave guard offers continue editing without losing local changes',
    (tester) async {
      final fixture = _Fixture();
      await _start(tester, fixture);
      await _change(tester);
      final leave = fixture.key.currentState!.requestExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(await leave, false);
      expect(find.text(_changed), findsOneWidget);
      expect(fixture.key.currentState!.session.dirty, true);
    },
  );

  testWidgets('save draft is explicit and never publishes', (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();
    expect(fixture.writes, [(title: _changed, publish: false)]);
    expect(fixture.draft, _changed);
    expect(fixture.published, _original);
    expect(fixture.key.currentState!.session.dirty, false);
  });

  testWidgets('publish requires its own explicit action', (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    await tester.tap(find.text('Publicar'));
    await tester.pumpAndSettle();
    expect(fixture.writes, [(title: _changed, publish: true)]);
    expect(fixture.published, _changed);
    expect(fixture.key.currentState!.session.dirty, false);
  });

  testWidgets('save when leaving saves draft and exits, without publishing', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    final leave = fixture.key.currentState!.requestExit();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar rascunho').last);
    await tester.pumpAndSettle();
    expect(await leave, true);
    expect(fixture.draft, _changed);
    expect(fixture.published, _original);
    expect(fixture.key.currentState!.session.active, false);
    expect(find.text(_original), findsOneWidget);
  });

  testWidgets(
    'authorization change clears local content and administrative state',
    (tester) async {
      final fixture = _Fixture();
      await _start(tester, fixture);
      await _change(tester);
      await tester.pumpWidget(fixture.page(admin: false));
      await tester.pumpAndSettle();
      expect(find.text(_original), findsOneWidget);
      expect(find.text(_changed), findsNothing);
      expect(find.byTooltip('Editar'), findsNothing);
      expect(find.text('Editando Home'), findsNothing);
      expect(fixture.key.currentState!.session.dirty, false);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authorization loss also dismisses the open text editor', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.tap(find.text('Toque para editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), _changed);
    await tester.pumpWidget(fixture.page(admin: false));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text(_changed), findsNothing);
    expect(fixture.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('published updates do not replace unsaved local edits', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    fixture.published = 'Encontre serviços, lazer e oportunidades em Macacu';
    await tester.pumpWidget(fixture.page());
    expect(find.text(_changed), findsOneWidget);
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text(fixture.published), findsOneWidget);
  });

  testWidgets('failed save retains local changes and pending state', (
    tester,
  ) async {
    final fixture = _Fixture()
      ..beforeSave = () async => throw StateError('offline');
    await _start(tester, fixture);
    await _change(tester);
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();
    expect(find.text(_changed), findsOneWidget);
    expect(fixture.key.currentState!.session.dirty, true);
    expect(fixture.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during a save does not update disposed state', (
    tester,
  ) async {
    final pending = Completer<void>();
    final fixture = _Fixture()..beforeSave = () => pending.future;
    await _start(tester, fixture);
    await _change(tester);
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'touch controls fit mobile widths and existing search still works',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [360.0, 393.0, 430.0]) {
        tester.view.physicalSize = Size(width, 1000);
        final fixture = _Fixture();
        await _start(tester, fixture);
        await tester.tap(find.text('O que você procura em Macacu?'));
        await tester.pump();
        expect(fixture.searches, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('empty title cannot be concluded or saved', (tester) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.tap(find.text('Toque para editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Concluir'));
    await tester.pump();
    expect(find.text('Informe o título.'), findsOneWidget);
    expect(fixture.key.currentState!.session.dirty, false);
    expect(fixture.writes, isEmpty);
  });

  testWidgets('authorization loss dismisses a pending exit confirmation', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    final leave = fixture.key.currentState!.requestExit();
    await tester.pumpAndSettle();
    expect(await fixture.key.currentState!.requestExit(), false);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpWidget(fixture.page(admin: false));
    await tester.pumpAndSettle();
    expect(await leave, false);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.key.currentState!.session.active, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back action uses the same pending changes guard', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _start(tester, fixture);
    await _change(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text(_changed), findsOneWidget);
    expect(fixture.key.currentState!.session.active, true);
  });

  testWidgets('landscape editor scrolls with the software keyboard visible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 420);
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final fixture = _Fixture();
    await _start(tester, fixture);
    await tester.ensureVisible(find.text('Toque para editar'));
    await tester.tap(find.text('Toque para editar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), _changed);
    await tester.ensureVisible(find.text('Concluir'));
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();
    expect(find.text(_changed), findsOneWidget);
    expect(fixture.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
