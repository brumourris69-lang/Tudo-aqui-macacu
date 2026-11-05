import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';

void main() {
  testWidgets('technology directory isolates category and subcategory', (
    tester,
  ) async {
    final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
    const data = [
      Business(
        'Internet fixture',
        'Tecnologia',
        'Provedores de internet',
        '',
        '',
        18,
      ),
      Business('Celular fixture', 'Tecnologia', 'Celulares', '', '', 18),
      Business('Outra categoria fixture', 'Comércio', 'Eletrônicos', '', '', 0),
    ];
    await tester.binding.setSurfaceSize(const Size(600, 2000));
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryView(
          category: category,
          businessesStream: Stream.value(data),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Internet fixture'), findsOneWidget);
    expect(find.text('Celular fixture'), findsOneWidget);
    expect(find.text('Outra categoria fixture'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Celulares'));
    await tester.pumpAndSettle();
    expect(find.text('Celular fixture'), findsOneWidget);
    expect(find.text('Internet fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('directory keeps an empty public response empty', (tester) async {
    final category = catalog.singleWhere((item) => item.name == 'Comércio');
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryView(
          category: category,
          businessesStream: Stream.value(const <Business>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Em breve, novos estabelecimentos aparecerão aqui.'),
      findsOneWidget,
    );
    expect(find.text('Dados demonstrativos.'), findsNothing);
    expect(find.text('Mercado do Centro'), findsNothing);
  });

  testWidgets('directory favorites use the app-owned saved IDs', (
    tester,
  ) async {
    final category = catalog.singleWhere((item) => item.name == 'Comércio');
    final savedIds = <String>{};
    var favoriteCalls = 0;
    const business = Business(
      'Saved fixture',
      'Comércio',
      'Demonstração',
      '',
      '',
      0,
      id: 'saved-fixture',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryView(
          category: category,
          businessesStream: Stream.value(const [business]),
          savedBusinessIds: savedIds,
          favoriteBusiness: (value) {
            favoriteCalls++;
            savedIds.add(value.favoriteKey);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final favorite = find.byTooltip('Favoritar Saved fixture');
    await tester.dragUntilVisible(
      favorite,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(favorite);
    await tester.pump();

    expect(favoriteCalls, 1);
    expect(savedIds, contains('saved-fixture'));
    expect(
      find.byTooltip('Remover dos favoritos Saved fixture'),
      findsOneWidget,
    );
  });

  testWidgets(
    'directory searches loaded business name description and location',
    (tester) async {
      final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
      const data = [
        Business(
          'Conecta Macacu',
          'Tecnologia',
          'Internet',
          'Fibra rápida',
          'Centro',
          18,
        ),
        Business(
          'Outro provedor',
          'Tecnologia',
          'Internet',
          'Bairro distante',
          'Papucaia',
          18,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryView(
            category: category,
            businessesStream: Stream.value(data),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('business-directory-search')),
        'fibra',
      );
      await tester.pumpAndSettle();
      expect(find.text('Conecta Macacu'), findsOneWidget);
      expect(find.text('Outro provedor'), findsNothing);
    },
  );

  testWidgets('directory empty state reflects both active search and filter', (
    tester,
  ) async {
    final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
    const data = [
      Business('Conecta Macacu', 'Tecnologia', 'Internet', '', 'Centro', 18),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryView(
          category: category,
          businessesStream: Stream.value(data),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Celulares'));
    await tester.enterText(
      find.byKey(const ValueKey('business-directory-search')),
      'Conecta',
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Nenhum estabelecimento corresponde à busca e ao filtro selecionado.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'all-business directory filters categories and removes duplicates',
    (tester) async {
      const provider = Business(
        'Elétrica Vieira',
        'Serviços',
        'Eletricistas',
        'Atendimento residencial',
        'Papucaia',
        0,
        id: 'eletrica-vieira',
      );
      const shop = Business(
        'Mercado Central',
        'Comércio',
        'Mercados',
        '',
        'Centro',
        0,
        id: 'mercado-central',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryView.all(
            businessesStreamFactory: () =>
                Stream.value([provider, provider, shop]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 resultados'), findsOneWidget);
      final directoryList = find.byType(ListView);
      await tester.dragUntilVisible(
        find.text('Mercado Central'),
        directoryList,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mercado Central'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Elétrica Vieira'),
        directoryList,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Elétrica Vieira'), findsOneWidget);

      final servicesFilter = find.widgetWithText(ChoiceChip, 'Serviços');
      await tester.dragUntilVisible(
        servicesFilter,
        directoryList,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      await tester.tap(servicesFilter);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Elétrica Vieira'),
        directoryList,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Elétrica Vieira'), findsOneWidget);
      expect(find.text('Mercado Central'), findsNothing);

      final search = find.byKey(const ValueKey('business-directory-search'));
      await tester.dragUntilVisible(
        search,
        directoryList,
        const Offset(0, 200),
      );
      await tester.enterText(search, 'eletrica papucaia');
      await tester.pumpAndSettle();
      expect(find.text('Elétrica Vieira'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open-now filter composes with category and search, then clears',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 2, 15); // Monday, noon in Brasília.
      const businesses = [
        Business(
          'Mercado Aberto',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'open-market',
          hours: 'Seg: 09:00 às 18:00',
        ),
        Business(
          'Serviço Aberto',
          'Serviços',
          'Manutenção',
          '',
          'Papucaia',
          0,
          id: 'open-service',
          hours: 'Seg: 10:00 às 17:00',
        ),
        Business(
          'Mercado Fechado',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'closed-market',
          hours: 'Seg: 08:00 às 11:00',
        ),
        Business(
          'Mercado sem horário',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'unknown-market',
        ),
        Business(
          'Mercado horário inválido',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'invalid-market',
          hours: 'Atendimento conforme agendamento',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryView.all(
            businessesStreamFactory: () => Stream.value(businesses),
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final openNow = find.byKey(const ValueKey('business-open-now-filter'));
      expect(openNow, findsOneWidget);
      await tester.tap(openNow);
      await tester.pumpAndSettle();
      expect(find.text('Mercado Aberto'), findsOneWidget);
      expect(find.text('Serviço Aberto'), findsOneWidget);
      expect(find.text('Mercado Fechado'), findsNothing);
      expect(find.text('Mercado sem horário'), findsNothing);
      expect(find.text('Mercado horário inválido'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Comércio'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('business-directory-search')),
        'aberto',
      );
      await tester.pumpAndSettle();
      expect(find.text('Mercado Aberto'), findsOneWidget);
      expect(find.text('Serviço Aberto'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('business-directory-search')),
        'sem resultado',
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Nenhum estabelecimento aberto agora corresponde a estes filtros.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.pumpAndSettle();
      expect(find.text('Mercado Aberto'), findsOneWidget);
      expect(find.text('Mercado Fechado'), findsNothing);

      await tester.tap(openNow);
      await tester.pumpAndSettle();
      expect(find.text('Mercado Fechado'), findsOneWidget);
      expect(find.text('Mercado sem horário'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Mercado horário inválido'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Mercado horário inválido'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'directory keeps default order and stably puts open businesses first',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 3, 2); // Monday 23:00 in Brasília.
      const businesses = [
        Business(
          'Sem horário primeiro',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'unknown-first',
        ),
        Business(
          'Aberto diurno',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'open-day',
          hours: 'Seg: 09:00 às 23:30',
        ),
        Business(
          'Fechado',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'closed',
          hours: 'Seg: 09:00 às 10:00',
        ),
        Business(
          'Aberto à noite',
          'Comércio',
          'Mercados',
          '',
          'Centro',
          0,
          id: 'open-overnight',
          hours: 'Seg: 22:00 às 02:00',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryView.all(
            businessesStreamFactory: () => Stream.value(businesses),
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const titles = [
        'Sem horário primeiro',
        'Aberto diurno',
        'Fechado',
        'Aberto à noite',
      ];
      List<String> visibleOrder() => [...titles]
        ..sort(
          (left, right) => tester
              .getTopLeft(find.text(left))
              .dy
              .compareTo(tester.getTopLeft(find.text(right)).dy),
        );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('business-sort-default')),
            )
            .selected,
        isTrue,
      );
      expect(visibleOrder(), orderedEquals(titles));

      await tester.tap(find.byKey(const ValueKey('business-sort-open-first')));
      await tester.pumpAndSettle();
      expect(
        visibleOrder(),
        orderedEquals([
          'Aberto diurno',
          'Aberto à noite',
          'Sem horário primeiro',
          'Fechado',
        ]),
      );

      await tester.tap(find.byKey(const ValueKey('business-sort-default')));
      await tester.pumpAndSettle();
      expect(visibleOrder(), orderedEquals(titles));
      await tester.tap(find.byKey(const ValueKey('business-sort-open-first')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Comércio'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('business-directory-search')),
        'aberto',
      );
      await tester.pumpAndSettle();
      expect(find.text('Aberto diurno'), findsOneWidget);
      expect(find.text('Aberto à noite'), findsOneWidget);
      expect(find.text('Sem horário primeiro'), findsNothing);
      expect(find.text('Fechado'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('business-open-now-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Aberto diurno'), findsOneWidget);
      expect(find.text('Aberto à noite'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('business-open-now-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Aberto diurno'), findsOneWidget);
      expect(find.text('Aberto à noite'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open-now control fits common phone widths and enlarged text', (
    tester,
  ) async {
    for (final width in <double>[320, 360, 412]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: DirectoryView.all(
            businessesStreamFactory: () => Stream.value(const <Business>[]),
            clock: () => DateTime.utc(2026, 11, 2, 15),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('business-open-now-filter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-sort-default')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-sort-open-first')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('business-sort-open-first')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('directory offers retry after an initial stream error', (
    tester,
  ) async {
    final firstAttempt = StreamController<List<Business>>();
    var attempts = 0;
    Stream<List<Business>> load() => ++attempts == 1
        ? firstAttempt.stream
        : Stream.value(const [
            Business(
              'Conecta recuperada',
              'Tecnologia',
              'Internet',
              '',
              'Centro',
              18,
            ),
          ]);
    final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
    await tester.pumpWidget(
      MaterialApp(
        home: DirectoryView(category: category, businessesStreamFactory: load),
      ),
    );
    firstAttempt.addError(StateError('offline'));
    await tester.pump();

    expect(
      find.text('Não foi possível carregar os estabelecimentos.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Conecta recuperada'), findsOneWidget);
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox());
    unawaited(firstAttempt.close());
  });

  testWidgets(
    'technology tile uses supplied wifi artwork and responds to tap',
    (tester) async {
      var tapped = false;
      final category = catalog.singleWhere((item) => item.name == 'Tecnologia');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 112,
                height: 155,
                child: CategoryTile(
                  category: category,
                  grid: true,
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tecnologia'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        AppIcon.technology.assetPath,
      );
      await tester.tap(find.text('Tecnologia'));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test('home respects configured order and existing category limit', () {
    final config = HomePageConfig.fromMap({
      'categoryOrder': ['Tecnologia', 'Comércio'],
      'sectionLimits': {'categories': 4},
    });
    final visible = config
        .categories(homeCatalog)
        .take(config.limitFor('categories'))
        .toList();
    expect(visible.first.name, 'Tecnologia');
    expect(visible, hasLength(4));
  });
}
