import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

class _CounterTab extends StatefulWidget {
  const _CounterTab({required this.label});
  final String label;
  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${widget.label}: $count'),
        FilledButton(
          onPressed: () => setState(() => count++),
          child: const Text('Incrementar'),
        ),
      ],
    ),
  );
}

void main() {
  test('primary Home categories keep existing route objects and order', () {
    final page = HomePageConfig.fromMap({});

    expect(
      page.primaryCategories(homeCatalog).map((item) => item.name),
      [
        'Comércio',
        'Onde comer?',
        'Serviços',
        'Profissionais',
        'Empregos',
        'Turismo',
        'Serviços úteis',
        'Eventos',
      ],
    );
    expect(
      page.primaryCategories(homeCatalog).first.types,
      homeCatalog.firstWhere((item) => item.name == 'Comércio').types,
    );
  });

  testWidgets('category grid adapts to narrow and wide layouts', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 360.0, 393.0, 430.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  HomeCategoryGrid(categories: homeCatalog.take(8).toList()),
                ],
              ),
            ),
          ),
        ),
      );
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        width < 420 ? 2 : 3,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('WelcomeHero exposes a profile shortcut accessibly', (
    tester,
  ) async {
    var openedProfile = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WelcomeHero(
            onSearch: () {},
            onProfile: () => openedProfile = true,
            user: null,
            config: HomePageConfig.fromMap({
              'visual': {'backgroundType': 'gradient'},
            }),
            weatherService: unavailableWeather(),
          ),
        ),
      ),
    );

    final profile = find.byTooltip('Perfil');
    expect(profile, findsOneWidget);
    final profileInkWell = find.descendant(
      of: profile,
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(profileInkWell), const Size(48, 48));
    await tester.tap(profile);
    expect(openedProfile, isTrue);
  });

  testWidgets('shell keeps five tabs, retains tab state and back returns Home', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CityShell(
          user: null,
          testPages: [
            const _CounterTab(label: 'Home fake'),
            const _CounterTab(label: 'Explorar fake'),
            const _CounterTab(label: 'Utilidades fake'),
            const _CounterTab(label: 'Favoritos fake'),
            const _CounterTab(label: 'Perfil fake'),
          ],
        ),
      ),
    );

    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navigation.destinations
          .cast<NavigationDestination>()
          .map((item) => item.label),
      ['Início', 'Explorar', 'Utilidades', 'Favoritos', 'Perfil'],
    );
    await tester.tap(find.text('Explorar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incrementar'));
    await tester.pump();
    expect(find.text('Explorar fake: 1'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('Home fake: 0'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.tap(find.text('Explorar').last);
    await tester.pumpAndSettle();
    expect(find.text('Explorar fake: 1'), findsOneWidget);
  });

}
