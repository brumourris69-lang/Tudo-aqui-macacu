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

  testWidgets('tourist spot card presents its stored subcategory', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TouristSpotCard(
          spot: TouristSpot.fromData('pocinho', {
            'title': 'Pocinho',
            'category': 'cachoeiras_pocos_lagoas',
            'subcategory': 'Poços e lagoas',
          }),
        ),
      ),
    );

    expect(find.text('Poços e lagoas'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets(
    'classificações de turismo voltam aos quatro espaços existentes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: TourismCategoryView(
            title: 'Pontos turísticos',
            categoryKey: 'pontos_turisticos',
            spots: [
              TouristSpot.fromData('roteiro', {
                'title': 'Roteiro legado',
                'category': 'roteiros_turisticos',
              }),
              TouristSpot.fromData('parque', {
                'title': 'Parque legado',
                'category': 'parques_reservas',
              }),
              TouristSpot.fromData('mirante', {
                'title': 'Mirante legado',
                'category': 'mirantes',
              }),
              TouristSpot.fromData('agua', {
                'title': 'Poço legado',
                'category': 'cachoeiras_pocos_lagoas',
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TouristSpotCard), findsNWidgets(4));
      expect(find.text('Roteiro legado'), findsOneWidget);
      expect(find.text('Parque legado'), findsOneWidget);
      expect(find.text('Mirante legado'), findsOneWidget);
      expect(find.text('Poço legado'), findsOneWidget);
      expect(find.text('Roteiros existentes'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    },
  );

  testWidgets('Guias turísticos permanece como espaço próprio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(
          title: 'Guias turísticos',
          categoryKey: 'guias_turisticos',
          spots: [
            TouristSpot.fromData('guide', {
              'title': 'Guia existente',
              'category': 'guias_turisticos',
            }),
            TouristSpot.fromData('route', {
              'title': 'Roteiro não é guia',
              'category': 'roteiros_turisticos',
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TouristSpotCard), findsOneWidget);
    expect(find.text('Guia existente'), findsOneWidget);
    expect(find.text('Roteiro não é guia'), findsNothing);
  });
}
