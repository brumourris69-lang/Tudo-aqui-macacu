import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';

void main() {
  testWidgets('technology directory isolates category and subcategory', (
    tester,
  ) async {
    final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
    const data = [
      Business(
        'Internet fixture',
        'Tecnologia',
        'Provedores de internet',
        '',
        '',
        18,
      ),
      Business('Celular fixture', 'Tecnologia', 'Celulares', '', '', 18),
      Business('Outra categoria fixture', 'Comércio', 'Eletrônicos', '', '', 0),
    ];
    await tester.binding.setSurfaceSize(const Size(600, 2000));
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryView(
          category: category,
          businessesStream: Stream.value(data),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Internet fixture'), findsOneWidget);
    expect(find.text('Celular fixture'), findsOneWidget);
    expect(find.text('Outra categoria fixture'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Celulares'));
    await tester.pumpAndSettle();
    expect(find.text('Celular fixture'), findsOneWidget);
    expect(find.text('Internet fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'technology tile uses supplied wifi artwork and responds to tap',
    (tester) async {
      var tapped = false;
      final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 112,
                height: 155,
                child: CategoryTile(
                  category: category,
                  grid: true,
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tecnologia'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AppIcon.technology.assetPath);
      await tester.tap(find.text('Tecnologia'));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test('home respects configured order and existing category limit', () {
    final config = HomePageConfig.fromMap({
      'categoryOrder': ['Tecnologia', 'Comércio'],
      'sectionLimits': {'categories': 4},
    });
    final visible = config
        .categories(homeCatalog)
        .take(config.limitFor('categories'))
        .toList();
    expect(visible.first.name, 'Tecnologia');
    expect(visible, hasLength(4));
  });
}
