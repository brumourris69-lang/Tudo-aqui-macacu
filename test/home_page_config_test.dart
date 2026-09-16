import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('a configuração publicada respeita ordem, visibilidade e limites', () {
    final config = HomePageConfig.fromMap({
      'sectionOrder': ['tourism', 'categories', 'offers'],
      'sections': {'tourism': true, 'categories': false, 'offers': true},
      'sectionLimits': {'offers': 4},
      'sectionTitles': {'tourism': 'Primeiro Macacu'},
    });

    expect(config.order, ['tourism', 'categories', 'offers']);
    expect(config.enabled('categories'), isFalse);
    expect(config.titleFor('tourism'), 'Primeiro Macacu');
    expect(config.limitFor('offers'), 4);
  });

  test('categorias seguem a ordem publicada e usam fallback seguro', () {
    final config = HomePageConfig.fromMap({
      'categoryOrder': ['Turismo', 'Comércio'],
      'sectionLimits': {'categories': 99},
    });
    final ordered = config.categories(homeCatalog);

    expect(ordered.first.name, 'Turismo');
    expect(ordered[1].name, 'Comércio');
    expect(config.limitFor('categories'), 12);
  });
}
