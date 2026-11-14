import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/mvp_launch_features.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/search/pages/beta_search_unavailable_page.dart';
import 'package:tudo_aqui_macacu/features/search/widgets/universal_search_bar.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

void main() {
  test('deferred public capabilities default to disabled', () {
    expect(MvpLaunchFeatures.reviewsEnabled, isFalse);
    expect(MvpLaunchFeatures.proposalsEnabled, isFalse);
    expect(MvpLaunchFeatures.votesEnabled, isFalse);
    expect(MvpLaunchFeatures.jobsEnabled, isFalse);
    expect(MvpLaunchFeatures.remotePushEnabled, isFalse);
    expect(MvpLaunchFeatures.isPublicHomeSectionEnabled('jobs'), isFalse);
    expect(MvpLaunchFeatures.isPublicHomeSectionEnabled('events'), isTrue);
    expect(MvpLaunchFeatures.isPublicHomeCategoryEnabled('Empregos'), isFalse);
    expect(MvpLaunchFeatures.isPublicHomeCategoryEnabled('Comércio'), isTrue);
  });

  test(
    'deferred capabilities cannot be enabled in profile or release builds',
    () {
      expect(
        MvpLaunchFeatures.deferredFeatureEnabled(
          debugBuild: false,
          requested: true,
        ),
        isFalse,
      );
      expect(
        MvpLaunchFeatures.deferredFeatureEnabled(
          debugBuild: true,
          requested: true,
        ),
        isTrue,
      );
    },
  );

  test('only active MVP user operations are permitted by the feature gate', () {
    expect(MvpLaunchFeatures.isUserOperationEnabled('favorite'), isTrue);
    expect(MvpLaunchFeatures.isUserOperationEnabled('unfavorite'), isTrue);
    expect(MvpLaunchFeatures.isUserOperationEnabled('contact'), isTrue);
    for (final operation in [
      'proposal',
      'review',
      'vote',
      'device',
      'removeDevice',
      'unknown',
    ]) {
      expect(
        MvpLaunchFeatures.isUserOperationEnabled(operation),
        isFalse,
        reason: '$operation must not write through the MVP 1.0 path',
      );
    }
    expect(MvpLaunchFeatures.isUserOperationEnabled('metric'), isTrue);
  });

  test('deferred public utilities are blocked while city utilities remain', () {
    expect(
      MvpLaunchFeatures.isPublicUtilityEnabled(
        id: 'community-polls',
        destination: 'polls',
      ),
      isFalse,
    );
    expect(
      MvpLaunchFeatures.isPublicUtilityEnabled(
        id: 'businessProposal',
        destination: 'businessProposal',
      ),
      isFalse,
    );
    expect(
      MvpLaunchFeatures.isPublicUtilityEnabled(
        id: 'waterEnergy',
        destination: 'waterEnergy',
      ),
      isTrue,
    );
  });

  testWidgets(
    'Home search follows the build switch and keeps the profile action',
    (tester) async {
      var profileOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WelcomeHero(
              onSearch: () {},
              onProfile: () => profileOpened = true,
              user: null,
              config: HomePageConfig.fromMap(const {}),
              weatherService: unavailableWeather(),
            ),
          ),
        ),
      );

      expect(
        find.byType(UniversalSearchBar),
        MvpLaunchFeatures.publicSearchEnabled ? findsOneWidget : findsNothing,
      );
      expect(find.byTooltip('Perfil'), findsOneWidget);
      expect(find.byTooltip('Notificações'), findsNothing);
      await tester.tap(find.byTooltip('Perfil'));
      expect(profileOpened, isTrue);
    },
  );

  testWidgets(
    'legacy Home search route shows existing guidance without search',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => homeSearchPage(
                      localSearch: false,
                      publicSearchEnabled: false,
                    ),
                  ),
                ),
                child: const Text('Abrir busca antiga'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir busca antiga'));
      await tester.pumpAndSettle();

      expect(find.byType(BetaSearchUnavailablePage), findsOneWidget);
      expect(find.byType(GlobalSearchView), findsNothing);
      expect(
        find.text('Busca por texto indisponível nesta versão'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Explore keeps categories and follows the search build switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreView(
          saved: const {},
          favorite: (_) {},
          businessesStreamFactory: () => Stream.value(const <Business>[]),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byTooltip('Buscar em Macacu'),
      MvpLaunchFeatures.publicSearchEnabled ? findsOneWidget : findsNothing,
    );
    expect(find.byType(HomeCategoryGrid), findsOneWidget);
    expect(find.text('Comércio'), findsOneWidget);
    expect(find.text('Empregos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deferred job category cannot open through a legacy route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openDirectory(
                context,
                const Category('Empregos', 4, ['Vagas']),
              ),
              child: const Text('Abrir categoria antiga'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir categoria antiga'));
    await tester.pumpAndSettle();

    expect(find.byType(LocalJobsView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deferred utilities cannot open their old public routes', (
    tester,
  ) async {
    final deferred = [
      const UtilityItem(
        id: 'community-polls',
        name: 'Enquetes',
        iconKey: 'poll',
        description: '',
        destinationType: 'internal',
        destination: 'polls',
        order: 1,
      ),
      const UtilityItem(
        id: 'businessProposal',
        name: 'Indique uma empresa',
        iconKey: 'business',
        description: '',
        destinationType: 'internal',
        destination: 'businessProposal',
        order: 2,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                for (final item in deferred)
                  TextButton(
                    onPressed: () => openUtilityDestination(context, item),
                    child: Text(item.name),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Enquetes'));
    await tester.pumpAndSettle();
    expect(find.byType(PollsView), findsNothing);
    await tester.tap(find.text('Indique uma empresa'));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessProposalView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'published utility list keeps city services but omits deferred items',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResourcesHub(
            utilitiesStreamFactory: () => Stream.value([
              const UtilityItem(
                id: 'community-polls',
                name: 'Enquetes',
                iconKey: 'poll',
                destinationType: 'internal',
                destination: 'polls',
                order: 1,
              ),
              const UtilityItem(
                id: 'businessProposal',
                name: 'Indique uma empresa',
                iconKey: 'business',
                destinationType: 'internal',
                destination: 'businessProposal',
                order: 2,
              ),
              const UtilityItem(
                id: 'waterEnergy',
                name: 'Conta de Água e Energia',
                iconKey: 'waterEnergy',
                destinationType: 'internal',
                destination: 'waterEnergy',
                order: 3,
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enquetes'), findsNothing);
      expect(find.text('Indique uma empresa'), findsNothing);
      expect(find.text('Conta de Água e Energia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
