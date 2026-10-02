import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_category.dart';

void main() {
  test('quatro categorias com chaves distintas e ordem definida', () {
    expect(TourismCategory.values.map((c) => c.key).toList(), [
      'cachoeiras',
      'trilhas',
      'pontos_turisticos',
      'roteiros',
    ]);
  });
  test(
    'categorias legadas preservam acesso e desconhecidas não são inventadas',
    () {
      expect(TourismCategory.normalize('Ponto turístico'), 'pontos_turisticos');
      expect(TourismCategory.normalize('route'), 'roteiros');
      expect(TourismCategory.normalize('Trilha'), 'trilhas');
      expect(TourismCategory.normalize('Outro'), 'outro');
    },
  );
}
