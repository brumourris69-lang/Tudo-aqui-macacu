import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('o catálogo cobre os serviços essenciais da cidade', () {
    final categories = catalog.map((item) => item.name).toSet();

    expect(categories, containsAll(<String>[
      'Comércio',
      'Onde comer?',
      'Serviços',
      'Turismo',
      'Saúde',
      'Serviços úteis',
    ]));
    expect(businesses, isNotEmpty);
    expect(featured, isNotEmpty);
  });
}
