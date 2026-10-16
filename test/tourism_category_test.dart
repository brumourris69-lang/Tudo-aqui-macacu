import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_category.dart';

void main() {
  test('quatro categorias com chaves distintas e ordem definida', () {
    expect(TourismCategory.values.map((c) => c.key).toList(), [
      'pontos_turisticos',
      'trilhas',
      'guias_turisticos',
      'historia_cidade',
    ]);
  });
  test(
    'categorias legadas preservam acesso e desconhecidas não são inventadas',
    () {
      expect(TourismCategory.normalize('Cachoeiras'), 'pontos_turisticos');
      expect(TourismCategory.normalize('guias_turisticos'), 'guias_turisticos');
      expect(TourismCategory.normalize('historia_cidade'), 'historia_cidade');
      expect(
        TourismCategory.normalize('História da cidade'),
        'historia_cidade',
      );
      expect(TourismCategory.normalize('route'), 'roteiros');
      expect(TourismCategory.normalize('Roteiros'), 'roteiros');
      expect(TourismCategory.normalize('Trilha'), 'trilhas');
      expect(TourismCategory.normalize('Outro'), 'outro');
    },
  );
}
