import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/home_favorites_section.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

void main() {
  testWidgets(
    'home favorites show at most six mixed public cards and actions',
    (tester) async {
      final openedBusinesses = <String>[];
      final openedSpots = <String>[];
      final removedBusinesses = <String>[];
      final removedSpots = <String>[];
      var openedAll = false;
      final businessIds = List.generate(4, (index) => 'business-$index');
      final spotIds = List.generate(4, (index) => 'spot-$index');
      final resolvedBusinessIds = <String>[];
      final resolvedSpotIds = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeFavoritesSection(
              businessIds: businessIds,
              tourismIds: spotIds,
              resolveBusiness: (id) async {
                resolvedBusinessIds.add(id);
                return _business(id);
              },
              resolveTourism: (id) async {
                resolvedSpotIds.add(id);
                return _spot(id);
              },
              onOpenBusiness: (item) => openedBusinesses.add(item.id),
              onOpenTourism: (item) => openedSpots.add(item.id),
              onRemoveBusiness: (item) => removedBusinesses.add(item.id),
              onRemoveTourism: (item) => removedSpots.add(item.id),
              onViewAll: () => openedAll = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seus Favoritos'), findsOneWidget);
      expect(find.text('Ver todos'), findsOneWidget);
      expect(resolvedBusinessIds.length + resolvedSpotIds.length, 6);
      expect(
        find.byKey(const ValueKey('home-favorite-card-business-business-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-favorite-card-tourism-spot-0')),
        findsOneWidget,
      );
      expect(find.text('Comércio'), findsAtLeastNWidgets(1));
      expect(find.text('Pontos turísticos'), findsAtLeastNWidgets(1));

      await tester.tap(
        find.byKey(const ValueKey('home-favorite-card-business-business-0')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('home-favorite-remove-business-business-0')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('home-favorite-card-tourism-spot-0')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('home-favorite-remove-tourism-spot-0')),
      );
      await tester.pump();
      await tester.tap(find.text('Ver todos'));

      expect(openedBusinesses, ['business-0']);
      expect(openedSpots, ['spot-0']);
      expect(removedBusinesses, ['business-0']);
      expect(removedSpots, ['spot-0']);
      expect(openedAll, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable saved content is omitted and large text fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(1.35),
          ),
          child: Scaffold(
            body: HomeFavoritesSection(
              businessIds: const ['visible', 'unpublished'],
              tourismIds: const [],
              resolveBusiness: (id) async =>
                  id == 'visible' ? _business(id) : null,
              resolveTourism: (_) async => null,
              onOpenBusiness: (_) {},
              onOpenTourism: (_) {},
              onRemoveBusiness: (_) {},
              onRemoveTourism: (_) {},
              onViewAll: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mercado visible'), findsOneWidget);
    expect(find.text('Mercado unpublished'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home hides the section for visitors and refreshes it for users',
    (tester) async {
      Stream<Map<String, dynamic>> config() => Stream.value({
        'sectionOrder': <String>[],
        'sections': {for (final section in defaultHomeOrder) section: false},
      });
      var resolutions = 0;
      Widget home({required User? user, required String favoriteId}) =>
          MaterialApp(
            home: HomeView(
              saved: {favoriteId},
              savedBusinessIds: {favoriteId},
              favorite: (_) {},
              showExplore: () {},
              user: user,
              configurationStreamFactory: config,
              weatherService: unavailableWeather(),
              resolveFavoriteBusiness: (id) async {
                resolutions++;
                return _business(id);
              },
              resolveFavoriteTourism: (_) async => null,
            ),
          );

      await tester.pumpWidget(home(user: null, favoriteId: 'guest-item'));
      await tester.pumpAndSettle();
      expect(find.text('Seus Favoritos'), findsNothing);
      expect(resolutions, 0);

      await tester.pumpWidget(
        home(user: _RegisteredUser(), favoriteId: 'account-item-1'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mercado account-item-1'), findsOneWidget);

      await tester.pumpWidget(
        home(user: _RegisteredUser(), favoriteId: 'account-item-2'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mercado account-item-1'), findsNothing);
      expect(find.text('Mercado account-item-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Business _business(String id) => Business(
  'Mercado $id',
  'Comércio',
  '',
  '',
  'Macacu',
  0,
  id: id,
  imageUrl: '',
);

TouristSpot _spot(String id) => TouristSpot.fromData(id, {
  'title': 'Lugar $id',
  'category': 'pontos_turisticos',
});

class _RegisteredUser implements User {
  @override
  String? get displayName => 'Morador';

  @override
  bool get isAnonymous => false;

  @override
  String get uid => 'home-favorites-user';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
