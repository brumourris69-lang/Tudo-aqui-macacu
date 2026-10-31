import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

Map<String, dynamic> _homeData(String title) => {
  'heroTitle': title,
  'sections': {for (final section in defaultHomeOrder) section: false},
  'visual': {'backgroundType': 'gradient'},
};

class _HomeStreams {
  final controllers = <StreamController<Map<String, dynamic>>>[];
  Stream<Map<String, dynamic>> create() {
    final controller = StreamController<Map<String, dynamic>>();
    controllers.add(controller);
    return controller.stream;
  }
}

Widget _home(_HomeStreams streams) => MaterialApp(
  home: Scaffold(
    body: HomeView(
      saved: <String>{},
      favorite: (_) {},
      showExplore: () {},
      user: null,
      configurationStreamFactory: streams.create,
      weatherService: unavailableWeather(),
    ),
  ),
);

Finder _editorSection(WidgetTester tester, String title) => find.ancestor(
  of: find.widgetWithText(SwitchListTile, title),
  matching: find.byType(Card),
).first;

Finder _homeEditorScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('home-editor-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollHomeEditorTo(WidgetTester tester, Finder target) async {
  final scrollable = tester.state<ScrollableState>(_homeEditorScrollable());
  final viewport = find.byKey(const ValueKey('home-editor-scroll'));
  for (var attempt = 0; attempt < 12; attempt++) {
    final targetRect = tester.getRect(target);
    final viewportRect = tester.getRect(viewport);
    if (targetRect.top >= viewportRect.top &&
        targetRect.bottom <= viewportRect.bottom) {
      return;
    }
    final delta = targetRect.bottom > viewportRect.bottom
        ? targetRect.bottom - viewportRect.bottom + 24
        : targetRect.top - viewportRect.top - 24;
    final next = (scrollable.position.pixels + delta)
        .clamp(
          scrollable.position.minScrollExtent,
          scrollable.position.maxScrollExtent,
        )
        .toDouble();
    scrollable.position.jumpTo(next);
    await tester.pumpAndSettle();
  }
  final targetRect = tester.getRect(target);
  final viewportRect = tester.getRect(viewport);
  expect(targetRect.top, greaterThanOrEqualTo(viewportRect.top));
  expect(targetRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
}

void main() {
  testWidgets('Home configuration shows loading then a recoverable error', (
    tester,
  ) async {
    final streams = _HomeStreams();
    await tester.pumpWidget(_home(streams));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    streams.controllers.single.addError(StateError('offline'));
    await tester.pump();
    expect(find.text('Não foi possível carregar a Home.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry loads config and a refresh error keeps prior content', (
    tester,
  ) async {
    final streams = _HomeStreams();
    await tester.pumpWidget(_home(streams));
    streams.controllers[0].add(_homeData('Home carregada'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Home carregada'), findsOneWidget);

    streams.controllers[0].addError(StateError('refresh failed'));
    await tester.pumpAndSettle();
    expect(find.text('Home carregada'), findsOneWidget);
    expect(find.text('Não foi possível atualizar a Home.'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(streams.controllers, hasLength(2));
    streams.controllers[1].add(_homeData('Home atualizada'));
    await tester.pump();
    expect(find.text('Home atualizada'), findsOneWidget);
    expect(find.text('Não foi possível atualizar a Home.'), findsNothing);
  });

  testWidgets('HomeEditor failure blocks writes until retry succeeds', (
    tester,
  ) async {
    var attempts = 0;
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeEditor(
          loadConfiguration: () async {
            if (attempts++ == 0) throw StateError('offline');
            return _homeData('Editor carregado');
          },
          saveConfiguration: (_, _) async => writes++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar a configuração da Home.'), findsOneWidget);
    expect(find.text('Salvar rascunho'), findsNothing);
    expect(find.text('Publicar alterações'), findsNothing);
    expect(writes, 0);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Editor carregado',
    );
    await tester.scrollUntilVisible(
      find.text('Salvar rascunho'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Salvar rascunho'), findsOneWidget);
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();
    expect(writes, 1);
  });

  testWidgets('HomeEditor round-trips section order, visibility, titles and limits', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    final published = _homeData('Home publicada');
    final originalOrder = List<String>.from(defaultHomeOrder);
    published['sectionOrder'] = originalOrder;
    published['sections'] = {for (final section in defaultHomeOrder) section: true};
    Map<String, dynamic>? draft;
    final writes = <bool>[];
    Map<String, dynamic> loadMerged() => mergeHomePageData(
      published,
      draft ?? const <String, dynamic>{},
    );

    Widget editor() => MaterialApp(
      home: HomeEditor(
        loadConfiguration: () async => loadMerged(),
        saveConfiguration: (data, publish) async {
          writes.add(publish);
          draft = Map<String, dynamic>.from(data);
          if (publish) published.addAll(data);
        },
      ),
    );

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    final dynamic editorState = tester.state(find.byType(HomeEditor));
    expect(editorState.loaded, isTrue);
    await _scrollHomeEditorTo(
      tester,
      find.widgetWithText(SwitchListTile, 'Categorias'),
    );
    final categoriesCard = _editorSection(tester, 'Categorias');
    final dragCategories = find.descendant(
      of: categoriesCard,
      matching: find.byIcon(Icons.drag_handle_rounded),
    );
    await tester.ensureVisible(dragCategories);
    await tester.drag(dragCategories, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(
      (tester.state(find.byType(HomeEditor)) as dynamic).order.first,
      'categories',
    );

    await _scrollHomeEditorTo(
      tester,
      find.widgetWithText(SwitchListTile, 'Turismo'),
    );
    final tourismCard = _editorSection(tester, 'Turismo');
    final tourismSwitch = find.descendant(
      of: tourismCard,
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(tourismSwitch);
    await tester.tap(tourismSwitch);
    await tester.pump();
    expect(find.text('Não aparece na Home publicada'), findsOneWidget);

    final fields = find.descendant(
      of: tourismCard,
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Roteiros da cidade');
    await tester.enterText(fields.at(1), '5');
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Salvar rascunho'),
      500,
      scrollable: _homeEditorScrollable(),
    );
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();

    expect(writes, [false]);
    expect(published['sectionOrder'], originalOrder);
    expect(draft!['sectionOrder'], ['categories', 'banner', ...originalOrder.skip(2)]);
    expect(draft!['sections']['tourism'], false);
    expect(draft!['sectionTitles']['tourism'], 'Roteiros da cidade');
    expect(draft!['sectionLimits']['tourism'], 5);

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    final dynamic reloadedState = tester.state(find.byType(HomeEditor));
    expect(reloadedState.loaded, isTrue);
    expect(reloadedState.order, draft!['sectionOrder']);
    expect(reloadedState.enabled['tourism'], false);
    expect(reloadedState.sectionTitles['tourism']!.text, 'Roteiros da cidade');
    expect(reloadedState.sectionLimits['tourism']!.text, '5');

    await tester.tap(find.text('Publicar alterações'));
    await tester.pumpAndSettle();
    expect(writes, [false, true]);
    expect(published['sectionOrder'], draft!['sectionOrder']);
    expect(published['sections']['tourism'], false);
    expect(published['sectionTitles']['tourism'], 'Roteiros da cidade');
    expect(published['sectionLimits']['tourism'], 5);
  });

  testWidgets('HomeEditor persists section appearance and reloads it', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    final published = _homeData('Home publicada');
    published['sections'] = {
      for (final section in defaultHomeOrder) section: true,
    };
    Map<String, dynamic>? draft;
    Widget editor() => MaterialApp(
      home: HomeEditor(
        loadConfiguration: () async =>
            mergeHomePageData(published, draft ?? const {}),
        saveConfiguration: (data, publish) async {
          draft = Map<String, dynamic>.from(data);
          if (publish) published.addAll(data);
        },
      ),
    );

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    final tourismAppearance = find.byKey(
      const ValueKey('home-section-appearance-tourism'),
    );
    await _scrollHomeEditorTo(tester, tourismAppearance);
    await tester.tap(tourismAppearance);
    await tester.pumpAndSettle();
    final description = find.byKey(
      const ValueKey('home-section-description-tourism'),
    );
    final image = find.byKey(const ValueKey('home-section-image-tourism'));
    expect(description, findsOneWidget);
    await tester.enterText(description, 'Natureza e aventuras locais');
    await tester.enterText(
      image,
      'https://res.cloudinary.com/demo/image/upload/tourism.jpg',
    );
    await tester.pump();
    final chooseIcon = find.descendant(
      of: tourismAppearance,
      matching: find.text('Escolher ícone'),
    );
    await _scrollHomeEditorTo(tester, chooseIcon);
    await tester.tap(chooseIcon);
    await tester.pumpAndSettle();
    final iconPicker = find.byType(VisualIconPicker).last;
    await tester.tap(
      find.descendant(
        of: iconPicker,
        matching: find.text('Eventos'),
      ),
    );
    await tester.tap(find.text('Usar este ícone'));
    await tester.pumpAndSettle();
    final editorScroll = tester.state<ScrollableState>(_homeEditorScrollable());
    editorScroll.position.jumpTo(editorScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Prévia do rascunho'), findsOneWidget);
    expect(find.text('Natureza e aventuras locais'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Salvar rascunho'),
      500,
      scrollable: _homeEditorScrollable(),
    );
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();
    expect(draft!['sectionDescriptions']['tourism'], 'Natureza e aventuras locais');
    expect(
      draft!['sectionImages']['tourism'],
      'https://res.cloudinary.com/demo/image/upload/tourism.jpg',
    );
    expect(
      draft!['sectionIcons']['tourism'],
      AppIcon.all.firstWhere((icon) => icon.label == 'Eventos').legacyIndex,
    );

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(HomeEditor));
    expect(state.sectionDescriptions['tourism']!.text, 'Natureza e aventuras locais');
    expect(
      state.sectionImages['tourism']!.text,
      'https://res.cloudinary.com/demo/image/upload/tourism.jpg',
    );
    expect(
      state.sectionIcons['tourism'],
      AppIcon.all.firstWhere((icon) => icon.label == 'Eventos').legacyIndex,
    );
  });

  testWidgets('HomeEditor cancellation restores saved draft without deleting it', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    final published = _homeData('Home publicada');
    Map<String, dynamic>? savedDraft = {'heroTitle': 'Título já salvo'};
    Widget editor() => MaterialApp(
      home: HomeEditor(
        loadConfiguration: () async =>
            mergeHomePageData(published, savedDraft ?? const {}),
        saveConfiguration: (data, publish) async {
          savedDraft = Map<String, dynamic>.from(data);
        },
      ),
    );

    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mudança não salva');
    await tester.scrollUntilVisible(
      find.text('Cancelar alterações não salvas'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cancelar alterações não salvas'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar edição?'), findsOneWidget);
    await tester.tap(find.text('Cancelar edição'));
    await tester.pumpAndSettle();

    expect(savedDraft, {'heroTitle': 'Título já salvo'});
    final editorScroll = tester.state<ScrollableState>(_homeEditorScrollable());
    editorScroll.position.jumpTo(editorScroll.position.minScrollExtent);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Título já salvo',
    );
  });

  testWidgets('HomeEditor reports save failure without exposing exception text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeEditor(
          loadConfiguration: () async => _homeData('Home teste'),
          saveConfiguration: (_, _) async =>
              throw StateError('private backend detail'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Salvar rascunho'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível salvar as alterações. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.text('private backend detail'), findsNothing);
  });

  testWidgets('HomeEditor stays usable at a narrow phone width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeEditor(
          loadConfiguration: () async => _homeData('Home no celular'),
          saveConfiguration: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rascunho e publicação'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ordem e visibilidade das seções'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ordem e visibilidade das seções'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Personalizar aparência').first,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Personalizar aparência').first, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
