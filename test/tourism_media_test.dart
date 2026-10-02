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
}
