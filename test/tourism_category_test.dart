import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_category.dart';

void main() {
  test('mantém somente os quatro espaços existentes', () {
    expect(TourismCategory.values.map((c) => c.key).toList(), [
      'pontos_turisticos',
      'trilhas',
      'guias_turisticos',
      'historia_cidade',
    ]);
  });

  test(
    'agrupa classificações novas nos espaços originais sem migrar dados',
    () {
      expect(
        [
          'cachoeiras_pocos_lagoas',
          'Cachoeiras',
          'Poços e lagoas',
          'parques_reservas',
          'roteiros_turisticos',
          'Roteiros turísticos',
          'mirantes',
          'Pontos turísticos',
        ].map(TourismCategory.normalize).toSet(),
        {'pontos_turisticos'},
      );
      expect(
        [
          'trilhas_montanhas',
          'Trilhas e montanhas',
          'Trilhas',
        ].map(TourismCategory.normalize).toSet(),
        {'trilhas'},
      );
      expect(TourismCategory.normalize('guias_turisticos'), 'guias_turisticos');
      expect(
        [
          'historia_cultura',
          'História e cultura',
          'historia_cidade',
        ].map(TourismCategory.normalize).toSet(),
        {'historia_cidade'},
      );
      expect(TourismCategory.normalize('Outro'), 'outro');
    },
  );
}
