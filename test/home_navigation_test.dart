import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/core/config/mvp_launch_features.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/features/search/pages/universal_search_page.dart';
import 'package:tudo_aqui_macacu/features/search/pages/beta_search_unavailable_page.dart';
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
  test('searchLocal routes Home search to the callable-backed search page', () {
    expect(homeSearchPage(localSearch: true), isA<UniversalSearchPage>());
    expect(
      homeSearchPage(localSearch: false, publicSearchEnabled: true),
      isA<GlobalSearchView>(),
    );
    expect(
      homeSearchPage(localSearch: false, publicSearchEnabled: false),
      isA<BetaSearchUnavailablePage>(),
    );
  });

  test(
    'Beta Home search entry is unavailable in the no-Functions Spark flavor',
    () {
      final page =
          homeSearchPage(localSearch: false, betaSearch: true)
              as BetaSearchUnavailablePage;
      expect(page, isA<BetaSearchUnavailablePage>());
    },
  );

  test('Search Local and Beta cannot be selected together', () {
    expect(
      () => homeSearchPage(localSearch: true, betaSearch: true),
      throwsArgumentError,
    );
  });

  test('primary Home categories keep existing route objects and order', () {
    final page = HomePageConfig.fromMap({});

    expect(page.primaryCategories(homeCatalog).map((item) => item.name), [
      'Comércio',
      'Onde comer?',
      'Serviços',
      'Profissionais',
      'Empregos',
      'Turismo',
      'Serviços úteis',
      'Eventos',
    ]);
    expect(
      page.primaryCategories(homeCatalog).first.types,
      homeCatalog.firstWhere((item) => item.name == 'Comércio').types,
    );
  });

  testWidgets('category grid adapts to narrow and wide layouts', (
    tester,
  ) async {
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

  testWidgets('Home search follows the explicit feature switch', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(393, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeView(
          saved: const {},
          favorite: (_) {},
          showExplore: () {},
          user: null,
          configurationStreamFactory: () => Stream.value({
            'sectionOrder': <String>[],
            'sections': {
              for (final section in defaultHomeOrder)
                section: section == 'categories',
            },
          }),
          weatherService: unavailableWeather(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (BetaEnvironment.enabled || !MvpLaunchFeatures.publicSearchEnabled) {
      expect(find.text('Buscar comércios, serviços e mais'), findsNothing);
      expect(find.byType(GlobalSearchView), findsNothing);
    } else {
      await tester.tap(find.text('Buscar comércios, serviços e mais'));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalSearchView), findsOneWidget);
    }
  });

  testWidgets(
    'shell keeps five tabs, retains tab state and back returns Home',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
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

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigation.destinations.cast<NavigationDestination>().map(
          (item) => item.label,
        ),
        ['Início', 'Explorar', 'Utilidades', 'Favoritos', 'Perfil'],
      );
      expect(navigation.indicatorColor, isNull);
      expect(
        Theme.of(
          tester.element(find.byType(NavigationBar)),
        ).navigationBarTheme.indicatorColor,
        AppColors.skyTint,
      );
      expect(
        Theme.of(tester.element(find.byType(NavigationBar)))
            .navigationBarTheme
            .labelTextStyle!
            .resolve(const {WidgetState.selected})!
            .fontFamily
            ?.startsWith('Poppins'),
        isTrue,
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
    },
  );
}
