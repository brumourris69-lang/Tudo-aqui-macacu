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
      'categoryIcons': {'Turismo': 11},
      'sectionLimits': {'categories': 99},
    });
    final ordered = config.categories(homeCatalog);

    expect(ordered.first.name, 'Turismo');
    expect(ordered[1].name, 'Comércio');
    expect(ordered.first.artwork, 11);
    expect(config.limitFor('categories'), 12);
  });

  test('fundo da Home preserva imagem e normaliza valores ausentes', () {
    final imageConfig = HomePageConfig.fromMap({
      'visual': {
        'backgroundType': 'image',
        'backgroundImageUrl':
            'https://res.cloudinary.com/demo/image/upload/home.jpg',
      },
    });

    expect(imageConfig.backgroundType, 'image');
    expect(
      imageConfig.backgroundImageUrl,
      'https://res.cloudinary.com/demo/image/upload/home.jpg',
    );
    expect(imageConfig.backgroundStart, 'EAF4FF');
    expect(imageConfig.backgroundEnd, 'F8FAFC');

    final invalidConfig = HomePageConfig.fromMap({
      'visual': {'backgroundType': 'video'},
    });

    expect(invalidConfig.backgroundType, 'gradient');
    expect(invalidConfig.backgroundImageUrl, isEmpty);
  });

  test('rascunho parcial nao apaga imagem publicada da Home', () {
    final merged = mergeHomePageData(
      {
        'visual': {
          'backgroundType': 'image',
          'backgroundImageUrl':
              'https://res.cloudinary.com/demo/image/upload/home.jpg',
          'backgroundStart': '001122',
        },
      },
      {
        'visual': {'slogan': 'Novo slogan'},
      },
    );
    final config = HomePageConfig.fromMap(merged);

    expect(config.slogan, 'Novo slogan');
    expect(config.backgroundType, 'image');
    expect(
      config.backgroundImageUrl,
      'https://res.cloudinary.com/demo/image/upload/home.jpg',
    );
    expect(config.backgroundStart, '001122');
  });
}
