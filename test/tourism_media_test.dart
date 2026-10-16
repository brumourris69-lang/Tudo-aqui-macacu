import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_cover.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('galeria descarta URLs inválidas e duplicadas mantendo a capa', () {
    final spot = TouristSpot.fromData('local', {
      'imageUrl': 'https://example.com/cover.jpg',
      'galleryUrls': [
        null,
        'inválida',
        'https://example.com/cover.jpg',
        'https://example.com/photo.jpg',
        'https://example.com/photo.jpg',
      ],
    });
    expect(spot.images, [
      'https://example.com/cover.jpg',
      'https://example.com/photo.jpg',
    ]);
    expect(
      TouristSpot.fromData('antigo', {'galleryUrls': 'inválida'}).images,
      isEmpty,
    );
  });
  testWidgets('local sem foto usa placeholder neutro no card e detalhes', (
    tester,
  ) async {
    final spot = TouristSpot.fromData('local', {'title': 'Local sem foto'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TouristSpotCard(spot: spot)),
        ),
      ),
    );
    expect(find.byType(TourismPlaceholder), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('Ver local'));
    await tester.pumpAndSettle();
    expect(find.byType(TouristSpotDetailView), findsOneWidget);
    expect(find.byType(TourismPlaceholder), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalhe de turismo não oferece compartilhar abrindo o mapa', (
    tester,
  ) async {
    final spot = TouristSpot.fromData('local', {
      'title': 'Local de teste',
      'maps': 'https://example.com/mapa',
    });
    await tester.pumpWidget(
      MaterialApp(home: TouristSpotDetailView(spot: spot)),
    );

    expect(find.text('Como chegar'), findsOneWidget);
    expect(find.byTooltip('Favoritar Local de teste'), findsOneWidget);
    expect(find.byTooltip('Compartilhar Local de teste'), findsNothing);
  });

  testWidgets('destino inválido não habilita ação de mapa', (tester) async {
    final spot = TouristSpot.fromData('local', {
      'title': 'Local inseguro',
      'maps': 'javascript:alert(1)',
    });
    await tester.pumpWidget(
      MaterialApp(home: TouristSpotDetailView(spot: spot)),
    );

    final mapButton = find.widgetWithText(FilledButton, 'Como chegar');
    expect(tester.widget<FilledButton>(mapButton).onPressed, isNull);
  });

  testWidgets('lista de categoria filtra lugares pela busca digitada', (
    tester,
  ) async {
    final spots = [
      TouristSpot.fromData('cachoeira', {
        'title': 'Cachoeira Azul',
        'location': 'Serra',
      }),
      TouristSpot.fromData('museu', {
        'title': 'Museu Municipal',
        'location': 'Centro',
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(title: 'Pontos turísticos', spots: spots),
      ),
    );

    await tester.enterText(find.byType(TextField), 'cachoeira');
    await tester.pump();

    expect(find.text('Cachoeira Azul'), findsOneWidget);
    expect(find.text('Museu Municipal'), findsNothing);
  });

  testWidgets('busca geral reconhece o nome visível da categoria', (
    tester,
  ) async {
    final spots = [
      TouristSpot.fromData('museu', {
        'title': 'Museu Municipal',
        'category': 'pontos_turisticos',
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(title: 'Pontos turísticos', spots: spots),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Pontos turísticos');
    await tester.pump();

    expect(find.text('Museu Municipal'), findsOneWidget);
  });

  testWidgets('busca sem correspondências mostra estado vazio específico', (
    tester,
  ) async {
    final spots = [
      TouristSpot.fromData('museu', {
        'title': 'Museu Municipal',
        'category': 'pontos_turisticos',
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(title: 'Pontos turísticos', spots: spots),
      ),
    );

    await tester.enterText(find.byType(TextField), 'sem resultado');
    await tester.pump();

    expect(find.text('Nenhum local corresponde à busca.'), findsOneWidget);
    expect(find.text('Museu Municipal'), findsNothing);
  });
}
