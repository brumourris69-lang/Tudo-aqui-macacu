import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_cover.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('galeria descarta URLs inválidas e duplicadas mantendo a capa', () {
    final spot = TouristSpot.fromData('local', {
      'imageUrl': 'https://example.com/cover.jpg',
      'galleryUrls': [
        null,
        'inválida',
        'https://example.com/cover.jpg',
        'https://example.com/photo.jpg',
        'https://example.com/photo.jpg',
      ],
    });
    expect(spot.images, [
      'https://example.com/cover.jpg',
      'https://example.com/photo.jpg',
    ]);
    expect(
      TouristSpot.fromData('antigo', {'galleryUrls': 'inválida'}).images,
      isEmpty,
    );
  });
  testWidgets('local sem foto usa placeholder neutro no card e detalhes', (
    tester,
  ) async {
    final spot = TouristSpot.fromData('local', {'title': 'Local sem foto'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TouristSpotCard(spot: spot)),
        ),
      ),
    );
    expect(find.byType(TourismPlaceholder), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage,
      ),
      findsNothing,
    );
    await tester.tap(find.text('Ver local'));
    await tester.pumpAndSettle();
    expect(find.byType(TouristSpotDetailView), findsOneWidget);
    expect(find.byType(TourismPlaceholder), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalhe de turismo compartilha texto sem abrir o mapa', (
    tester,
  ) async {
    String? sharedText;
    final spot = TouristSpot.fromData('local', {
      'title': 'Local de teste',
      'description': 'Descrição pública.',
      'maps': 'https://example.com/mapa',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TouristSpotDetailView(
          spot: spot,
          onShare: (content) async => sharedText = content.message,
        ),
      ),
    );

    expect(find.text('Como chegar'), findsOneWidget);
    expect(find.byTooltip('Favoritar Local de teste'), findsOneWidget);
    await tester.tap(find.byTooltip('Compartilhar Local de teste'));
    await tester.pump();
    expect(sharedText, contains('Local de teste'));
    expect(sharedText, contains('Descrição pública.'));
    expect(sharedText, isNot(contains('example.com/mapa')));
  });

  testWidgets('sem localização válida o detalhe oculta ação de mapa', (
    tester,
  ) async {
    final spot = TouristSpot.fromData('local', {
      'title': 'Local inseguro',
      'maps': 'javascript:alert(1)',
    });
    await tester.pumpWidget(
      MaterialApp(home: TouristSpotDetailView(spot: spot)),
    );

    expect(find.text('Como chegar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('endereço cadastrado abre busca do mapa com o texto existente', (
    tester,
  ) async {
    String? openedDestination;
    final spot = TouristSpot.fromData('local-com-endereco', {
      'title': 'Local com endereço',
      'address': 'Praça da Matriz, Cachoeiras de Macacu',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TouristSpotDetailView(
          spot: spot,
          onOpenMap: (destination) async => openedDestination = destination,
        ),
      ),
    );

    await tester.tap(find.text('Como chegar'));
    await tester.pump();

    final uri = Uri.parse(openedDestination!);
    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(
      uri.queryParameters['query'],
      'Praça da Matriz, Cachoeiras de Macacu',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha ao abrir mapa mostra mensagem e não quebra a tela', (
    tester,
  ) async {
    final spot = TouristSpot.fromData('local', {
      'title': 'Local com mapa',
      'maps': 'https://maps.google.com/local',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TouristSpotDetailView(
          spot: spot,
          onOpenMap: (_) async => throw StateError('launcher indisponível'),
        ),
      ),
    );

    await tester.tap(find.text('Como chegar'));
    await tester.pump();

    expect(find.text('Não foi possível abrir o mapa.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalhe turístico evita overflow em larguras móveis ampliadas', (
    tester,
  ) async {
    final originalSize = tester.view.physicalSize;
    final originalRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalRatio;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final spot = TouristSpot.fromData('local', {
      'title': 'Atrativo com nome longo para teste de responsividade',
      'location': 'Endereço cadastrado com uma descrição longa da localização',
      'maps': 'https://maps.google.com/local',
      'description':
          'Descrição pública longa para validar texto ampliado. ' * 4,
      'additionalInfo': 'Leve água e calçado adequado.',
    });

    for (final width in [320.0, 360.0, 412.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: MaterialApp(home: TouristSpotDetailView(spot: spot)),
        ),
      );
      await tester.pump();
      expect(find.text('Como chegar'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });

  testWidgets('lista de categoria filtra lugares pela busca digitada', (
    tester,
  ) async {
    if (BetaEnvironment.enabled) {
      await tester.pumpWidget(
        MaterialApp(
          home: TourismCategoryView(
            title: 'Pontos turísticos',
            spots: [
              TouristSpot.fromData('cachoeira', {'title': 'Cachoeira Azul'}),
            ],
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Cachoeira Azul'), findsOneWidget);
      expect(tester.takeException(), isNull);
      return;
    }
    final spots = [
      TouristSpot.fromData('cachoeira', {
        'title': 'Cachoeira Azul',
        'location': 'Serra',
      }),
      TouristSpot.fromData('museu', {
        'title': 'Museu Municipal',
        'location': 'Centro',
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(title: 'Pontos turísticos', spots: spots),
      ),
    );

    await tester.enterText(find.byType(TextField), 'cachoeira');
    await tester.pump();

    expect(find.text('Cachoeira Azul'), findsOneWidget);
    expect(find.text('Museu Municipal'), findsNothing);
  });

  testWidgets('busca geral reconhece o nome visível da categoria', (
    tester,
  ) async {
    if (BetaEnvironment.enabled) {
      await tester.pumpWidget(
        MaterialApp(
          home: TourismCategoryView(
            title: 'Pontos turísticos',
            spots: [
              TouristSpot.fromData('museu', {'title': 'Museu Municipal'}),
            ],
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Museu Municipal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      return;
    }
    final spots = [
      TouristSpot.fromData('museu', {
        'title': 'Museu Municipal',
        'category': 'pontos_turisticos',
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(title: 'Pontos turísticos', spots: spots),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Pontos turísticos');
    await tester.pump();

    expect(find.text('Museu Municipal'), findsOneWidget);
  });

  testWidgets('busca sem correspondências mostra estado vazio específico', (
    tester,
  ) async {
    if (BetaEnvironment.enabled) {
      await tester.pumpWidget(
        MaterialApp(
          home: TourismCategoryView(
            title: 'Pontos turísticos',
            spots: const [],
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      return;
    }
    final spots = [
      TouristSpot.fromData('museu', {
        'title': 'Museu Municipal',
        'category': 'pontos_turisticos',
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(title: 'Pontos turísticos', spots: spots),
      ),
    );

    await tester.enterText(find.byType(TextField), 'sem resultado');
    await tester.pump();

    expect(find.text('Nenhum local corresponde à busca.'), findsOneWidget);
    expect(find.text('Museu Municipal'), findsNothing);
  });
}
