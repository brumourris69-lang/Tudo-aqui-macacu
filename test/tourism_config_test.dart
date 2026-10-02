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
}
