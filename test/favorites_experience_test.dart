import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/auth/local_demo_login.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('My favorites separates businesses and tourism by saved ID', (
    tester,
  ) async {
    final business = Business(
      'Mercado Favorito',
      'Mercado',
      '',
      '',
      '',
      0,
      id: 'business-1',
    );
    final otherBusiness = Business(
      'Outro Mercado',
      'Mercado',
      '',
      '',
      '',
      0,
      id: 'business-2',
    );
    final spot = TouristSpot.fromData('spot-1', {
      'title': 'Cachoeira Favorita',
      'category': 'pontos_turisticos',
    });
    final otherSpot = TouristSpot.fromData('spot-2', {
      'title': 'Outra Cachoeira',
      'category': 'pontos_turisticos',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SavedView(
          saved: {'business-1'},
          savedTourismIds: {'spot-1'},
          favorite: (_) {},
          favoriteTourism: (_) {},
          businessesStreamFactory: () =>
              Stream.value([business, otherBusiness]),
          tourismStreamFactory: () => Stream.value([spot, otherSpot]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mercado Favorito'), findsOneWidget);
    expect(find.text('Outro Mercado'), findsNothing);
    await tester.tap(find.text('Pontos Turísticos'));
    await tester.pumpAndSettle();
    expect(find.text('Cachoeira Favorita'), findsOneWidget);
    expect(find.text('Outra Cachoeira'), findsNothing);
  });

  testWidgets(
    'visitor favorite prompt offers sign-in without blocking browsing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('Conteúdo público continua aberto'),
                  TextButton(
                    onPressed: () => promptFavoriteSignIn(context),
                    child: const Text('Favoritar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Favoritar'));
      await tester.pumpAndSettle();
      expect(find.text('Entre para salvar seus favoritos'), findsOneWidget);
      expect(find.text('Conteúdo público continua aberto'), findsOneWidget);
      await tester.tap(find.text('Entrar ou criar conta'));
      await tester.pumpAndSettle();
      if (localDemoLoginEnabled) {
        expect(find.byKey(const Key('local-demo-email')), findsOneWidget);
        expect(find.byKey(const Key('local-demo-password')), findsOneWidget);
        expect(find.byKey(const Key('open-email-auth')), findsNothing);
      } else {
        expect(find.text('Continuar com Google'), findsOneWidget);
        expect(find.byKey(const Key('open-email-auth')), findsOneWidget);
      }
    },
  );

  testWidgets('visitor agenda action asks for sign-in only when saving', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('A agenda pública permanece disponível'),
                TextButton(
                  onPressed: () => promptAgendaSignIn(context),
                  child: const Text('Adicionar à agenda'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('A agenda pública permanece disponível'), findsOneWidget);
    await tester.tap(find.text('Adicionar à agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Entre para salvar na sua agenda'), findsOneWidget);
    expect(find.text('Agora não'), findsOneWidget);
    expect(find.text('A agenda pública permanece disponível'), findsOneWidget);
  });

  testWidgets(
    'empty favorites remain readable on narrow screens with larger text',
    (tester) async {
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
            child: SavedView(
              saved: const <String>{},
              savedTourismIds: const <String>{},
              favorite: _ignoreBusiness,
              favoriteTourism: _ignoreTourism,
              businessesStreamFactory: () => Stream.value(const <Business>[]),
              tourismStreamFactory: () => Stream.value(const <TouristSpot>[]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Os estabelecimentos que você salvar aparecerão aqui.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Pontos Turísticos'));
      await tester.pumpAndSettle();
      expect(
        find.text('Os pontos turísticos que você salvar aparecerão aqui.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

void _ignoreBusiness(Business _) {}

void _ignoreTourism(TouristSpot _) {}
