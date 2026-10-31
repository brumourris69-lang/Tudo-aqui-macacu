import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('tourism share is available publicly and hidden in Admin view', (
    tester,
  ) async {
    final spot = TouristSpot.fromData('spot-share', {
      'title': 'Cachoeira Modelo',
      'description': 'Descrição pública breve.',
    });
    await tester.pumpWidget(MaterialApp(home: TouristSpotCard(spot: spot)));
    expect(find.byTooltip('Compartilhar Cachoeira Modelo'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(home: TouristSpotCard(spot: spot, admin: true)),
    );
    expect(find.byTooltip('Compartilhar Cachoeira Modelo'), findsNothing);
  });
  testWidgets('tourist spot cards expose an accessible favorite action', (
    tester,
  ) async {
    var favorites = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TouristSpotCard(
          spot: TouristSpot.fromData('spot-1', {'title': 'Cachoeira Modelo'}),
          saved: true,
          onFavorite: () => favorites++,
        ),
      ),
    );

    expect(find.byTooltip('Desfavoritar Cachoeira Modelo'), findsOneWidget);
    await tester.tap(find.byTooltip('Desfavoritar Cachoeira Modelo'));
    expect(favorites, 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });

  testWidgets('Admin pode abrir a edição direta de um item publicado', (
    tester,
  ) async {
    String? editedId;
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(
          title: 'Pontos turísticos',
          categoryKey: 'pontos_turisticos',
          admin: true,
          onEditSpot: (spot) => editedId = spot.id,
          spots: [
            TouristSpot.fromData('spot-1', {
              'title': 'Local cadastrado',
              'category': 'pontos_turisticos',
              'published': true,
              'active': true,
            }),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Editar Local cadastrado'));
    expect(editedId, 'spot-1');
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });

  testWidgets('categoria de guias mantém roteiros legados em grupo separado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(
          title: 'Guias turísticos',
          categoryKey: 'guias_turisticos',
          spots: [
            TouristSpot.fromData('roteiro', {
              'title': 'Roteiro legado',
              'category': 'roteiros',
            }),
            TouristSpot.fromData('guia', {
              'title': 'Guia histórico',
              'category': 'guias_turisticos',
            }),
          ],
        ),
      ),
    );
    final categoryList = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Roteiro legado'),
      250,
      scrollable: categoryList,
    );
    expect(find.text('Roteiro legado'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Guia histórico'),
      250,
      scrollable: categoryList,
    );
    expect(find.text('Guia histórico'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Roteiros existentes'),
      250,
      scrollable: categoryList,
    );
    expect(find.text('Roteiros existentes'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });
}
