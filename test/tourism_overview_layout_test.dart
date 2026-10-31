import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_config.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_overview.dart';

void main() {
  testWidgets('tourism overview category cards stay compact on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TourismOverview(
                config: TourismConfig.fromMap(const {}),
                admin: false,
                onCategoryTap: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    final categoryCard = find.byKey(
      const ValueKey('tourism-category-pontos_turisticos'),
    );
    expect(categoryCard, findsOneWidget);
    expect(tester.getSize(categoryCard).height, lessThanOrEqualTo(176));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tourism overview remains usable at narrow width and larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  TourismOverview(
                    config: TourismConfig.fromMap(const {
                      'categories': {
                        'pontos_turisticos': {
                          'description': 'Conteúdo descritivo para a categoria',
                        },
                      },
                    }),
                    admin: false,
                    onCategoryTap: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Pontos turísticos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
