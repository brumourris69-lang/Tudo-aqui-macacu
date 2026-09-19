import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('o catálogo cobre os serviços essenciais da cidade', () {
    final categories = catalog.map((item) => item.name).toSet();

    expect(
      categories,
      containsAll(<String>[
        'Comércio',
        'Onde comer?',
        'Serviços',
        'Turismo',
        'Saúde',
        'Serviços úteis',
      ]),
    );
    expect(businesses, isNotEmpty);
    expect(featured, isNotEmpty);
  });

  test('empresa usa id estavel para favoritos quando disponivel', () {
    const business = Business(
      'Nome antigo',
      'Comércio',
      'Loja',
      'Descrição',
      'Centro',
      0,
      id: 'doc-estavel-123',
    );

    expect(business.favoriteKey, 'doc-estavel-123');
  });

  test('url do Cloudinary recebe transformação otimizada', () {
    final optimized = cloudinaryOptimizedImageUrl(
      'https://res.cloudinary.com/demo/image/upload/v1/foto.jpg',
    );

    expect(
      optimized,
      'https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/v1/foto.jpg',
    );
  });
}
