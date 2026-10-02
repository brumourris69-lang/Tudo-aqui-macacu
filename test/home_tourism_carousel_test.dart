import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/home_tourism_carousel.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_config.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_cover.dart';

void main() {
  testWidgets('uses Tourism names, covers, order and active visibility', (
    tester,
  ) async {
    final config = TourismConfig.fromMap({
      'categories': {
        'cachoeiras': {'active': false},
        'trilhas': {
          'name': 'Trilhas locais',
          'order': -1,
          'imageUrl': 'https://example.com/trilha.jpg',
        },
      },
    });
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTourismCarousel(
            config: config,
            onCategoryTap: (category) => selected = category.key,
          ),
        ),
      ),
    );
    final cards = tester.widgetList<TourismCover>(find.byType(TourismCover));
    expect(cards.length, 3);
    expect(cards.first.title, 'Trilhas locais');
    expect(cards.first.imageUrl, config.categories.first.imageUrl);
    expect(find.text('Cachoeiras'), findsNothing);
    expect(find.text('Explore Macacu'), findsOneWidget);
    expect(find.text('Explorar agora'), findsNothing);
    expect(find.text('Explore por categoria'), findsNothing);
    await tester.tap(find.text('Trilhas locais'));
    expect(selected, 'trilhas');
  });

  testWidgets('horizontal cards fit phone widths and enlarged text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 360.0, 412.0, 600.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: HomeTourismCarousel(
                config: TourismConfig.fromMap({}),
                onCategoryTap: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TourismCover), findsNWidgets(4));
      expect(find.byType(TourismPlaceholder), findsNWidgets(4));
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-900, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('no active categories leaves no empty section', (tester) async {
    final config = TourismConfig.fromMap({});
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTourismCarousel(
          config: TourismConfig.fromMap({
            'categories': {
              for (final category in config.categories)
                category.key: {'active': false},
            },
          }),
          onCategoryTap: (_) {},
        ),
      ),
    );
    expect(find.text('Explore Macacu'), findsNothing);
    expect(find.byType(TourismCover), findsNothing);
  });
}
