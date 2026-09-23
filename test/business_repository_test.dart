import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/repositories/business_repository.dart';

void main() {
  test('BusinessRepository.featuredBusinesses preserva somente destaques', () {
    const businesses = [
      Business('Publicado comum', 'Comércio', '', '', 'Centro', 0, id: 'comum'),
      Business(
        'Publicado destaque',
        'Serviços',
        '',
        '',
        'Centro',
        0,
        id: 'destaque',
        featured: true,
      ),
    ];

    final featured = BusinessRepository.featuredBusinesses(businesses);

    expect(featured, hasLength(1));
    expect(featured.single.id, 'destaque');
  });
}
