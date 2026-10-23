import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

const _adminOrder = <String>[
  'Turismo',
  'Comércio',
  'Onde comer?',
  'Serviços',
  'Profissionais',
  'Empregos',
  'Serviços úteis',
  'Eventos',
];

Map<String, dynamic> _configuration(List<String> categoryOrder) => {
  'sectionOrder': ['categories'],
  'sections': {
    for (final section in defaultHomeOrder) section: section == 'categories',
  },
  'sectionLimits': {'categories': categoryOrder.length},
  'categoryOrder': categoryOrder,
  'visual': {'backgroundType': 'gradient'},
};

Widget _home({
  required double textScale,
  List<String> categoryOrder = _adminOrder,
  GlobalKey<NavigatorState>? navigatorKey,
  List<Route<dynamic>>? pushedRoutes,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [if (pushedRoutes != null) _RouteRecorder(pushedRoutes)],
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: HomeView(
          saved: const <String>{},
          favorite: (_) {},
          showExplore: () {},
          user: null,
          configurationStreamFactory: () =>
              Stream.value(_configuration(categoryOrder)),
          weatherService: unavailableWeather(),
        ),
      ),
    ),
  ),
);

class _RouteRecorder extends NavigatorObserver {
  _RouteRecorder(this.routes);
  final List<Route<dynamic>> routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

Finder get _rail => find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);

List<String> _visibleCategoryNames(WidgetTester tester) {
  final railRect = tester.getRect(_rail);
  final tiles = find.byType(CategoryTile);
  final visible = <(double left, String name)>[];
  for (var index = 0; index < tiles.evaluate().length; index++) {
    final tile = tiles.at(index);
    final rect = tester.getRect(tile);
    if (rect.right > railRect.left && rect.left < railRect.right) {
      visible.add((rect.left, tester.widget<CategoryTile>(tile).category.name));
    }
  }
  visible.sort((a, b) => a.$1.compareTo(b.$1));
  return visible.map((item) => item.$2).toList(growable: false);
}

void main() {
  testWidgets(
    'Home category rail remains usable across supported widths and text scales',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final width in [320.0, 360.0, 393.0, 480.0]) {
        for (final textScale in [1.0, 1.8]) {
          await tester.binding.setSurfaceSize(Size(width, 900));
          await tester.pumpWidget(_home(textScale: textScale));
          await tester.pumpAndSettle();
          final scrollable = tester.state<ScrollableState>(
            find.descendant(of: _rail, matching: find.byType(Scrollable)).first,
          );
          scrollable.position.jumpTo(0);
          await tester.pumpAndSettle();

          expect(
            _rail,
            findsOneWidget,
            reason: 'width=$width scale=$textScale',
          );
          final layoutException = tester.takeException();
          expect(
            layoutException,
            isNull,
            reason: 'width=$width scale=$textScale: $layoutException',
          );

          final firstTile = tester.widget<CategoryTile>(
            find.byType(CategoryTile).first,
          );
          expect(firstTile.category.name, 'Turismo');
          expect(tester.getSize(find.byType(CategoryTile).first).width, 82);
          final firstTileSemantics = tester
              .getSemantics(find.byType(CategoryTile).first)
              .getSemanticsData();
          expect(firstTileSemantics.label, 'Turismo');
          expect(firstTileSemantics.hasAction(SemanticsAction.tap), isTrue);

          final position = scrollable.position;
          final encountered = <String>[];
          for (
            var offset = 0.0;
            offset < position.maxScrollExtent;
            offset += 50
          ) {
            position.jumpTo(offset);
            await tester.pump();
            for (final name in _visibleCategoryNames(tester)) {
              if (encountered.isEmpty || encountered.last != name) {
                if (!encountered.contains(name)) encountered.add(name);
              }
            }
          }
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          for (final name in _visibleCategoryNames(tester)) {
            if (!encountered.contains(name)) encountered.add(name);
          }
          expect(encountered, _adminOrder);
          expect(find.bySemanticsLabel('Eventos'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'scroll width=$width scale=$textScale',
          );
        }
      }
    },
  );

  testWidgets('Home category actions open their assigned destinations', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(393, 900));
    final destinations = <String, Type>{
      'Comércio': DirectoryView,
      'Onde comer?': DirectoryView,
      'Serviços': DirectoryView,
      'Profissionais': DirectoryView,
      'Empregos': LocalJobsView,
      'Turismo': TourismHomeView,
      'Serviços úteis': PublicServicesView,
      'Eventos': EventsReminderView,
    };

    for (final entry in destinations.entries) {
      final navigatorKey = GlobalKey<NavigatorState>();
      final routes = <Route<dynamic>>[];
      final configuredOrder = [
        entry.key,
        ..._adminOrder.where((name) => name != entry.key),
      ];
      await tester.pumpWidget(
        _home(
          textScale: 1,
          categoryOrder: configuredOrder,
          navigatorKey: navigatorKey,
          pushedRoutes: routes,
        ),
      );
      await tester.pumpAndSettle();

      final tile = tester.widget<CategoryTile>(find.byType(CategoryTile).first);
      expect(tile.category.name, entry.key);
      final semanticsNode = tester.getSemantics(
        find.byType(CategoryTile).first,
      );
      expect(
        semanticsNode.getSemanticsData().label,
        entry.key == 'Serviços úteis' ? 'Utilidades da Cidade' : entry.key,
      );
      expect(
        semanticsNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      tile.onTap();

      final route = routes.last;
      expect(route, isA<MaterialPageRoute<dynamic>>());
      final target = (route as MaterialPageRoute<dynamic>).builder(
        navigatorKey.currentContext!,
      );
      expect(target.runtimeType, entry.value);
      if (target is DirectoryView) {
        expect(target.category.name, entry.key);
        expect(
          target.category.types,
          homeCatalog.firstWhere((item) => item.name == entry.key).types,
        );
      }
    }
  });
}
