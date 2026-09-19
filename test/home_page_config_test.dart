import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
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

  testWidgets('cabecalho da Home renderiza em larguras Android comuns', (
    tester,
  ) async {
    final config = HomePageConfig.fromMap({
      'heroTitle': 'Encontre serviços, lazer e oportunidades em Macacu',
      'searchPlaceholder': 'Buscar em Cachoeiras de Macacu',
      'visual': {
        'backgroundType': 'gradient',
        'slogan': 'A cidade na sua mão.',
      },
    });

    for (final width in [360.0, 393.0, 430.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WelcomeHero(onSearch: () {}, user: null, config: config),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Tudo Aqui Macacu'), findsOneWidget);
      expect(find.text('26° · Macacu'), findsOneWidget);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
