import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/admin_authorization.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

class _AdminUser implements User {
  @override
  bool get isAnonymous => false;
  @override
  String get uid => 'home-admin-fixture';
  @override
  String? get displayName => 'Admin';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _homeConfig = <String, dynamic>{
  'heroTitle': 'O que você procura hoje?',
  'sections': {
    'banner': false,
    'categories': false,
    'highlights': false,
    'offers': false,
    'resources': false,
    'jobs': false,
    'events': false,
    'tourism': false,
  },
};

Widget _home({
  required bool admin,
  Map<String, dynamic> config = _homeConfig,
  HomeConfigurationSaveCallback? saveConfiguration,
}) {
  final authorization = AdminAuthorization()
    ..value = const AdminClaimState(uid: 'home-admin-fixture', allowed: true);
  return AdminAuthorizationScope(
    authorization: authorization,
    child: MaterialApp(
      home: Scaffold(
        body: HomeView(
          saved: const {},
          favorite: (_) {},
          showExplore: () {},
          user: admin ? _AdminUser() : null,
          configurationStreamFactory: () => Stream.value(config),
          saveConfiguration: saveConfiguration,
          weatherService: unavailableWeather(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('admin enters the full visual editor from the Home action', (
    tester,
  ) async {
    await tester.pumpWidget(_home(admin: true));
    await tester.pumpAndSettle();

    final editHome = find.byTooltip('Editar Home');
    expect(editHome, findsOneWidget);
    await tester.tap(editHome);
    await tester.pumpAndSettle();

    expect(find.text('Modo administrativo ativo'), findsOneWidget);
    expect(find.byTooltip('Sair da edição Home'), findsOneWidget);
    expect(find.text('Textos'), findsOneWidget);
    expect(find.text('Visual'), findsOneWidget);
    expect(find.byTooltip('Editar seções'), findsOneWidget);
    await tester.tap(find.text('O que você procura hoje?'));
    await tester.pumpAndSettle();
    expect(find.text('Editando Home'), findsOneWidget);
  });

  testWidgets(
    'admin can leave visual edit mode without opening the title tool',
    (tester) async {
      await tester.pumpWidget(_home(admin: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sair da edição Home'));
      await tester.pumpAndSettle();

      expect(find.text('Modo administrativo ativo'), findsNothing);
      expect(find.text('Textos'), findsNothing);
      expect(find.byTooltip('Editar Home'), findsOneWidget);
    },
  );

  testWidgets('admin can open the text editor directly from Home edit mode', (
    tester,
  ) async {
    await tester.pumpWidget(_home(admin: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar Home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Textos'));
    await tester.pumpAndSettle();

    expect(find.text('Editar topo da Home'), findsOneWidget);
    expect(find.text('Título principal'), findsOneWidget);
    expect(find.text('Publicar'), findsOneWidget);
  });

  testWidgets(
    'saving a Home draft closes the editor without disposing live text fields',
    (tester) async {
      Map<String, dynamic>? saved;
      String? savedLabel;
      var published = true;
      await tester.pumpWidget(
        _home(
          admin: true,
          saveConfiguration: (data, {required label, required publish}) async {
            saved = data;
            savedLabel = label;
            published = publish;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar Home'));
      await tester.pumpAndSettle();
      for (var cycle = 1; cycle <= 3; cycle++) {
        await tester.tap(find.text('Textos'));
        await tester.pumpAndSettle();

        final draftTitle = 'Rascunho sintético $cycle';
        await tester.enterText(find.byType(TextField).first, draftTitle);
        await tester.tap(find.text('Salvar rascunho'));
        await tester.pumpAndSettle();

        expect(saved?['heroTitle'], draftTitle);
        expect(savedLabel, 'Topo da Home editado');
        expect(published, isFalse);
        expect(find.text('Editar topo da Home'), findsNothing);
        expect(find.text('O que você procura hoje?'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Sair da edição Home'));
        await tester.pumpAndSettle();
        expect(find.text('Textos'), findsNothing);
        await tester.tap(find.byTooltip('Editar Home'));
        await tester.pumpAndSettle();
        expect(find.text('O que você procura hoje?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('admin can edit each Home section appearance in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      _home(
        admin: true,
        config: {
          ..._homeConfig,
          'sections': {..._homeConfig['sections'] as Map, 'categories': true},
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar Home'));
    await tester.pumpAndSettle();
    final editSection = find.byTooltip('Editar seção').first;
    await tester.ensureVisible(editSection);
    await tester.tap(editSection);
    await tester.pumpAndSettle();

    expect(find.text('Editar Categorias'), findsOneWidget);
    expect(find.text('Título da seção'), findsOneWidget);
    expect(find.text('Descrição'), findsOneWidget);
    expect(find.text('Imagem da seção (URL)'), findsOneWidget);
    expect(find.text('Ícone da seção'), findsOneWidget);
    expect(find.text('Prévia da seção'), findsOneWidget);
    expect(find.text('Salvar rascunho'), findsOneWidget);
    expect(find.text('Publicar'), findsOneWidget);
  });

  testWidgets('admin can open visual identity editor from Home edit mode', (
    tester,
  ) async {
    await tester.pumpWidget(_home(admin: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar Home'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Visual'));
    await tester.pumpAndSettle();

    expect(find.text('Identidade visual'), findsOneWidget);
    expect(find.text('Tipo de fundo'), findsOneWidget);
    expect(find.text('Publicar'), findsOneWidget);
  });

  testWidgets('admin can open the section order and visibility editor', (
    tester,
  ) async {
    await tester.pumpWidget(_home(admin: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar seções'));
    await tester.pumpAndSettle();

    expect(find.text('Seções da Home'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-section-title-categories')),
      findsOneWidget,
    );
    expect(
      find.text('Arraste para reorganizar. Nada é salvo até tocar em salvar.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'admin can edit a Home shortcut directly without changing route',
    (tester) async {
      await tester.pumpWidget(
        _home(
          admin: true,
          config: {
            ..._homeConfig,
            'sections': {..._homeConfig['sections'] as Map, 'categories': true},
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar Home'));
      await tester.pumpAndSettle();

      final editShortcut = find.byTooltip('Editar atalho Comércio');
      await tester.ensureVisible(editShortcut);
      await tester.tap(editShortcut);
      await tester.pumpAndSettle();

      expect(find.text('Editar atalho'), findsOneWidget);
      expect(find.text('Destino: Comércio'), findsOneWidget);
      expect(find.text('Nome exibido'), findsOneWidget);
      expect(find.text('Imagem do atalho (URL)'), findsOneWidget);
      expect(find.text('Mostrar na Home publicada'), findsOneWidget);
      expect(find.text('Salvar rascunho'), findsOneWidget);
      expect(find.text('Publicar'), findsOneWidget);
      expect(find.byType(NamedVisualIconPicker), findsOneWidget);
    },
  );

  testWidgets('home editor saves named shortcut fields and visibility', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    var published = true;
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeEditor(
          loadConfiguration: () async => {
            'categoryOrder': ['Comércio', 'Eventos'],
            'categoryIcons': {'Comércio': 0},
          },
          saveConfiguration: (data, publish) async {
            saved = data;
            published = publish;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final commerceCard = find.byKey(
      const ValueKey('home-category-shortcut-Comércio'),
    );
    final dragHandle = find.descendant(
      of: commerceCard,
      matching: find.byType(ReorderableDragStartListener),
    );
    // ReorderableListView handles are the only draggable region in each row.
    expect(dragHandle, findsOneWidget);
    final eventsCard = find.byKey(
      const ValueKey('home-category-shortcut-Eventos'),
    );
    final dragDistance =
        tester
            .getCenter(
              find.descendant(
                of: eventsCard,
                matching: find.byType(ReorderableDragStartListener),
              ),
            )
            .dy -
        tester.getCenter(dragHandle).dy +
        80;
    await tester.timedDragFrom(
      tester.getCenter(dragHandle),
      Offset(0, dragDistance),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    final label = find.byKey(const ValueKey('home-category-label-Comércio'));
    await tester.ensureVisible(label);
    await tester.enterText(label, 'Lojas da cidade');
    final image = find.byKey(const ValueKey('home-category-image-Comércio'));
    await tester.ensureVisible(image);
    await tester.enterText(image, 'https://example.invalid/shop.jpg');
    final visibility = find.byKey(
      const ValueKey('home-category-visible-Comércio'),
    );
    await tester.ensureVisible(visibility);
    await tester.tap(visibility);
    await tester.pump();

    final iconButton = find.descendant(
      of: find.byKey(const ValueKey('home-category-shortcut-Comércio')),
      matching: find.text('Ícone'),
    );
    await tester.ensureVisible(iconButton);
    await tester.tap(iconButton);
    await tester.pumpAndSettle();
    final newIcon = find.byKey(const ValueKey('named-home-icon-eventos'));
    await tester.ensureVisible(newIcon);
    await tester.tap(newIcon);
    await tester.pump();
    await tester.tap(find.text('Usar este ícone'));
    await tester.pumpAndSettle();

    final saveDraft = find.text('Salvar rascunho');
    await tester.ensureVisible(saveDraft);
    await tester.tap(saveDraft);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(published, isFalse);
    final order = (saved!['categoryOrder'] as List).cast<String>();
    expect(order.indexOf('Comércio'), greaterThan(order.indexOf('Eventos')));
    expect((saved!['categoryIcons'] as Map)['Comércio'], 'eventos');
    expect((saved!['categoryLabels'] as Map)['Comércio'], 'Lojas da cidade');
    expect(
      (saved!['categoryImages'] as Map)['Comércio'],
      'https://example.invalid/shop.jpg',
    );
    expect((saved!['categoryVisible'] as Map)['Comércio'], isFalse);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('ordinary user cannot see or activate Home editing tools', (
    tester,
  ) async {
    await tester.pumpWidget(_home(admin: false));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Editar Home'), findsNothing);
    expect(find.text('Modo administrativo'), findsNothing);
    expect(find.text('Textos'), findsNothing);
    expect(find.text('Visual'), findsNothing);
  });

  testWidgets(
    'public Home shows only configured shortcut labels and visibility',
    (tester) async {
      await tester.pumpWidget(
        _home(
          admin: false,
          config: {
            ..._homeConfig,
            'sections': {..._homeConfig['sections'] as Map, 'categories': true},
            'categoryLabels': {'Comércio': 'Lojas Macacu'},
            'categoryIcons': {'Comércio': 'eventos'},
            'categoryVisible': {'Onde comer?': false},
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lojas Macacu'), findsOneWidget);
      expect(find.text('Onde comer?'), findsNothing);
      expect(find.byTooltip('Editar atalho Comércio'), findsNothing);
    },
  );
}
