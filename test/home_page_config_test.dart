import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'support/weather_fixture.dart';

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
      'categoryIcons': {'Comércio': 11},
      'sectionLimits': {'categories': 99},
    });
    final ordered = config.categories(homeCatalog);

    expect(ordered.first.name, 'Turismo');
    expect(ordered.any((category) => category.name == 'Turismo'), isTrue);
    expect(exploreCatalog.any((category) => category.name == 'Turismo'), isFalse);
    expect(
      ordered.firstWhere((category) => category.name == 'Comércio').artwork,
      11,
    );
    expect(config.limitFor('categories'), 12);
  });

  test('ordem parcial preserva a ordem original das categorias omitidas', () {
    const source = [
      Category('Eventos', 1, ['events']),
      Category('Serviços', 2, ['services']),
      Category('Turismo', 3, ['routes']),
      Category('Comércio', 4, ['businesses']),
      Category('Empregos', 5, ['jobs']),
    ];
    final config = HomePageConfig.fromMap({
      'categoryOrder': ['Turismo', 'Eventos'],
    });

    expect(
      config.categories(source).map((category) => category.name),
      ['Turismo', 'Eventos', 'Serviços', 'Comércio', 'Empregos'],
    );
  });

  test('atalhos principais complementam ordem parcial pelo padrão aprovado', () {
    const source = [
      Category('Eventos', 1, ['events']),
      Category('Serviços úteis', 2, ['resources']),
      Category('Turismo', 3, ['routes']),
      Category('Serviços', 4, ['services']),
      Category('Comércio', 5, ['businesses']),
      Category('Empregos', 6, ['jobs']),
      Category('Profissionais', 7, ['professionals']),
      Category('Onde comer?', 8, ['food']),
    ];
    final config = HomePageConfig.fromMap({
      'categoryOrder': ['Eventos'],
      'categoryIcons': {'Serviços úteis': 22},
    });

    final primary = config.primaryCategories(source);

    expect(primary.map((category) => category.name), [
      'Eventos',
      'Comércio',
      'Onde comer?',
      'Serviços',
      'Profissionais',
      'Empregos',
      'Turismo',
      'Serviços úteis',
    ]);
    expect(primary.map((category) => category.name).toSet().length, primary.length);
    expect(primary.last.artwork, 22);
    expect(primary.last.types, source[1].types);
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

    expect(invalidConfig.backgroundType, 'image');
    expect(invalidConfig.backgroundImageUrl, homeWaterfallBackgroundAsset);
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

  test('configuração completa preserva ordem, visibilidade e visual', () {
    final config = HomePageConfig.fromMap({
      'heroTitle': 'O que você procura hoje?',
      'searchPlaceholder': 'Encontre em Macacu...',
      'sectionOrder': [
        'banner',
        'categories',
        'highlights',
        'offers',
        'resources',
        'jobs',
        'events',
        'tourism',
      ],
      'sections': {
        'banner': true,
        'categories': true,
        'highlights': true,
        'offers': true,
        'resources': true,
        'jobs': true,
        'events': true,
        'tourism': true,
      },
      'sectionTitles': {
        'categories': 'Categorias',
        'highlights': 'Tá bombando em Macacu 🔥',
        'offers': 'Ofertas em Macacu',
        'resources': 'Cupons em Macacu',
        'jobs': 'Novos por aqui',
        'events': 'O que tá rolando',
        'tourism': 'Descubra Macacu',
        'eventsAgenda': 'Agenda Macacu',
      },
      'sectionLimits': {
        'banner': 2,
        'categories': 12,
        'highlights': 6,
        'offers': 2,
        'resources': 2,
        'jobs': 2,
        'events': 2,
        'tourism': 2,
      },
      'visual': {
        'slogan': 'A cidade na sua mão.',
        'greeting': 'A cidade na sua mão.',
        'location': 'Cachoeiras de Macacu • RJ',
        'logoUrl': '',
        'backgroundType': 'image',
        'backgroundStart': 'EAF4FF',
        'backgroundEnd': 'F8FAFC',
        'backgroundImageUrl': homeWaterfallBackgroundAsset,
      },
    });

    expect(config.order, defaultHomeOrder);
    expect(defaultHomeOrder.every(config.enabled), isTrue);
    expect(config.titleFor('highlights'), 'Tá bombando em Macacu 🔥');
    expect(config.eventAgendaTitle, 'Agenda Macacu');
    expect(config.limitFor('categories'), 12);
    expect(config.limitFor('highlights'), 6);
    expect(config.backgroundType, 'image');
    expect(config.backgroundImageUrl, homeWaterfallBackgroundAsset);
    expect(config.backgroundStart, 'EAF4FF');
    expect(config.backgroundEnd, 'F8FAFC');
    expect(config.slogan, 'A cidade na sua mão.');
    expect(config.greeting, 'A cidade na sua mão.');
    expect(config.location, 'Cachoeiras de Macacu • RJ');
    expect(config.logoUrl, '');
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
            body: WelcomeHero(
              onSearch: () {},
              user: null,
              config: config,
              weatherService: unavailableWeather(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Tudo Aqui Macacu'), findsOneWidget);
      expect(find.text('Cachoeiras de Macacu • RJ'), findsOneWidget);
      expect(find.text('26° · Macacu'), findsNothing);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
