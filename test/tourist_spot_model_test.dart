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

  test(
    'limita a galeria exibida a três imagens sem alterar os dados salvos',
    () {
      final spot = TouristSpot.fromData('galeria-longa', {
        'imageUrl': 'https://example.com/capa.jpg',
        'galleryUrls': [
          'https://example.com/foto-1.jpg',
          'https://example.com/foto-2.jpg',
          'https://example.com/foto-3.jpg',
        ],
      });

      expect(spot.images, hasLength(3));
      expect(spot.images.first, contains('capa.jpg'));
      expect(spot.images.last, contains('foto-2.jpg'));
    },
  );

  test('usa link legado como mapa apenas com URL HTTPS segura', () {
    final safeLink = TouristSpot.fromData('link', {
      'link': 'https://example.com/roteiro',
    });
    final unsafeLink = TouristSpot.fromData('unsafe-link', {
      'link': 'javascript:alert(1)',
    });
    final unsafeMap = TouristSpot.fromData('unsafe-map', {
      'maps': 'javascript:alert(1)',
    });

    expect(safeLink.maps, 'https://example.com/roteiro');
    expect(unsafeLink.maps, isEmpty);
    expect(unsafeMap.maps, isEmpty);
  });

  test('TouristSpot.fromData usa fallbacks quando campos faltam', () {
    final spot = TouristSpot.fromData('sem-campos', const {});

    expect(spot.id, 'sem-campos');
    expect(spot.title, 'Local turístico');
    expect(spot.category, '');
    expect(spot.description, '');
    expect(spot.location, '');
    expect(spot.maps, '');
    expect(spot.images, isEmpty);
    expect(spot.additionalInfo, '');
  });

  test('mapa explícito prevalece ao link legado', () {
    final spot = TouristSpot.fromData('roteiro-link', {
      'title': 'Roteiro Centro',
      'link': 'https://example.com/roteiro',
      'maps': 'https://maps.google.com/rota',
      'galleryUrls': [null, ' https://example.com/foto.jpg '],
    });

    expect(spot.maps, 'https://maps.google.com/rota');
    expect(spot.images, ['https://example.com/foto.jpg']);
  });
}
