import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_config.dart';

void main() {
  test('documento antigo usa defaults neutros nos quatro espaços', () {
    final config = TourismConfig.fromMap({});
    expect(config.categories.map((c) => c.key), [
      'pontos_turisticos',
      'trilhas',
      'guias_turisticos',
      'historia_cidade',
    ]);
    expect(config.imageUrl, isEmpty);
    expect(
      config.categories.every((c) => c.imageUrl.isEmpty && c.active),
      isTrue,
    );
    expect(TourismConfig.fromMap(config.toMap()).toMap(), config.toMap());
  });

  test('configuração dos espaços existentes preserva ordem e visibilidade', () {
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

  test('campos malformados usam os quatro espaços originais', () {
    final config = TourismConfig.fromMap({'categories': 'antigo'});
    expect(config.categories.length, 4);
  });

  test('configuração antiga de Cachoeiras continua em Pontos turísticos', () {
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

  test('configuração legada de Roteiros alimenta Pontos turísticos', () {
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
    final points = config.categories.singleWhere(
      (category) => category.key == 'pontos_turisticos',
    );

    expect(points.name, 'Pontos turísticos');
    expect(points.description, 'Texto legado');
    expect(points.imageUrl, 'https://example.com/roteiros.jpg');
    expect(points.order, 2);
    expect(points.active, isTrue);
    expect(config.toMap()['categories'], isNot(contains('roteiros')));
    expect(
      config.categories.singleWhere((c) => c.key == 'guias_turisticos').active,
      isTrue,
    );
  });

  test('subcategorias novas preservam aparência sem criar espaços', () {
    final config = TourismConfig.fromMap({
      'categories': {
        'parques_reservas': {
          'name': 'Parques e reservas',
          'description': 'Texto local',
          'imageUrl': 'https://example.com/parques.jpg',
          'active': true,
        },
        'historia_cultura': {'description': 'Memória local', 'active': false},
      },
    });

    expect(config.categories.length, 4);
    final points = config.categories.singleWhere(
      (category) => category.key == 'pontos_turisticos',
    );
    final history = config.categories.singleWhere(
      (category) => category.key == 'historia_cidade',
    );
    expect(points.name, 'Pontos turísticos');
    expect(points.description, 'Texto local');
    expect(points.imageUrl, 'https://example.com/parques.jpg');
    expect(history.name, 'História da cidade');
    expect(history.description, 'Memória local');
    expect(history.active, isFalse);
  });

  test(
    'Pontos turísticos só se oculta quando todas as subcategorias inativam',
    () {
      final config = TourismConfig.fromMap({
        'categories': {
          for (final key in [
            'cachoeiras_pocos_lagoas',
            'parques_reservas',
            'roteiros_turisticos',
            'roteiros',
            'mirantes',
          ])
            key: {'active': false},
        },
      });
      expect(
        config.categories
            .singleWhere((c) => c.key == 'pontos_turisticos')
            .active,
        isFalse,
      );
    },
  );

  test('configuração canônica de Pontos prevalece sobre subcategoria', () {
    final config = TourismConfig.fromMap({
      'categories': {
        'cachoeiras_pocos_lagoas': {'description': 'Subcategoria'},
        'pontos_turisticos': {'description': 'Canônica', 'active': true},
      },
    });
    final points = config.categories.singleWhere(
      (category) => category.key == 'pontos_turisticos',
    );

    expect(points.description, 'Canônica');
    expect(points.active, isTrue);
  });
}
