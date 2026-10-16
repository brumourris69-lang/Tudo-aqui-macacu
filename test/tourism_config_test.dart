import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_config.dart';

void main() {
  test('documento antigo usa defaults neutros sem fotos', () {
    final config = TourismConfig.fromMap({});
    expect(config.categories.length, 4);
    expect(config.imageUrl, isEmpty);
    expect(
      config.categories.every((c) => c.imageUrl.isEmpty && c.active),
      isTrue,
    );
    expect(TourismConfig.fromMap(config.toMap()).toMap(), config.toMap());
  });
  test('config preserva capa, ordem e visibilidade sem criar categorias', () {
    final config = TourismConfig.fromMap({
      'categories': {
        'trilhas': {
          'name': 'Caminhadas',
          'order': -1,
          'active': false,
          'imageUrl': 'https://example.com/real.jpg',
        },
        'outra': {'name': 'Ignorar'},
      },
    });
    expect(config.categories.first.key, 'trilhas');
    expect(config.categories.first.name, 'Caminhadas');
    expect(config.categories.first.active, isFalse);
    expect(config.categories.first.imageUrl, 'https://example.com/real.jpg');
    expect(config.categories.length, 4);
  });
  test('campos malformados possuem fallback seguro', () {
    final config = TourismConfig.fromMap({'categories': 'antigo'});
    expect(config.categories.length, 4);
  });

  test('config antiga de roteiros fornece aparência de Guias sem migração', () {
    final config = TourismConfig.fromMap({
      'categories': {
        'roteiros': {
          'name': 'Roteiros personalizados',
          'description': 'Texto legado',
          'imageUrl': 'https://example.com/roteiros.jpg',
          'order': 2,
          'active': false,
        },
      },
    });
    final guides = config.categories.singleWhere(
      (category) => category.key == 'guias_turisticos',
    );

    expect(guides.name, 'Guias turísticos');
    expect(guides.description, 'Texto legado');
    expect(guides.imageUrl, 'https://example.com/roteiros.jpg');
    expect(guides.order, 2);
    expect(guides.active, isFalse);
    expect(config.toMap()['categories'], isNot(contains('roteiros')));
  });

  test('pontos turísticos usa configuração Cachoeiras legada', () {
    final config = TourismConfig.fromMap({
      'categories': {
        'cachoeiras': {
          'name': 'Cachoeiras antigas',
          'description': 'Texto legado',
          'imageUrl': 'https://example.com/cachoeiras.jpg',
          'order': 3,
          'active': false,
        },
      },
    });
    final points = config.categories.singleWhere(
      (category) => category.key == 'pontos_turisticos',
    );

    expect(points.name, 'Pontos turísticos');
    expect(points.description, 'Texto legado');
    expect(points.imageUrl, 'https://example.com/cachoeiras.jpg');
    expect(points.order, 3);
    expect(points.active, isFalse);
  });

  test('configuração atual de Pontos turísticos prevalece sobre Cachoeiras', () {
    final config = TourismConfig.fromMap({
      'categories': {
        'cachoeiras': {'description': 'Legado', 'active': false},
        'pontos_turisticos': {
          'description': 'Atual',
          'active': true,
        },
      },
    });
    final points = config.categories.singleWhere(
      (category) => category.key == 'pontos_turisticos',
    );

    expect(points.description, 'Atual');
    expect(points.active, isTrue);
  });
}
