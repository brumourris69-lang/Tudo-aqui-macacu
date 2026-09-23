import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';

void main() {
  test('TouristSpot.fromData preserva documento completo', () {
    final spot = TouristSpot.fromData('cachoeira-1', {
      'title': 'Cachoeira Bonita',
      'category': 'Cachoeiras',
      'description': 'Queda dágua com poço natural',
      'location': 'Serra de Macacu',
      'maps': 'https://maps.google.com/cachoeira',
      'imageUrl': 'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
      'galleryUrls': [
        'https://res.cloudinary.com/demo/image/upload/v1/foto1.jpg',
        'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
        '',
      ],
      'additionalInfo': 'Leve água e calçado adequado',
    });

    expect(spot.id, 'cachoeira-1');
    expect(spot.title, 'Cachoeira Bonita');
    expect(spot.category, 'cachoeiras');
    expect(spot.description, 'Queda dágua com poço natural');
    expect(spot.location, 'Serra de Macacu');
    expect(spot.maps, 'https://maps.google.com/cachoeira');
    expect(spot.images, hasLength(2));
    expect(spot.images.first, contains('/f_auto,q_auto,w_1600,c_limit/'));
    expect(spot.images.first, contains('/capa.jpg'));
    expect(spot.additionalInfo, 'Leve água e calçado adequado');
  });

  test('TouristSpot.fromData preserva fallbacks legados', () {
    final spot = TouristSpot.fromData('trilha-antiga', {
      'name': 'Trilha antiga',
      'type': 'Trilha',
      'address': 'Boca da mata',
      'mapsUrl': 'https://maps.google.com/trilha',
    });

    expect(spot.id, 'trilha-antiga');
    expect(spot.title, 'Trilha antiga');
    expect(spot.category, 'trilha');
    expect(spot.description, '');
    expect(spot.location, 'Boca da mata');
    expect(spot.maps, 'https://maps.google.com/trilha');
    expect(spot.images, isEmpty);
    expect(spot.additionalInfo, '');
  });

  test('TouristSpot.fromData usa fallbacks quando campos faltam', () {
    final spot = TouristSpot.fromData('sem-campos', const {});

    expect(spot.id, 'sem-campos');
    expect(spot.title, 'Local turístico');
    expect(spot.category, 'cachoeiras');
    expect(spot.description, '');
    expect(spot.location, '');
    expect(spot.maps, '');
    expect(spot.images, isEmpty);
    expect(spot.additionalInfo, '');
  });

  test('TouristSpot.fromData usa link como fallback de mapa', () {
    final spot = TouristSpot.fromData('roteiro-link', {
      'title': 'Roteiro Centro',
      'link': 'https://example.com/roteiro',
      'galleryUrls': [null, ' https://example.com/foto.jpg '],
    });

    expect(spot.maps, 'https://example.com/roteiro');
    expect(spot.images, ['null', 'https://example.com/foto.jpg']);
  });
}
