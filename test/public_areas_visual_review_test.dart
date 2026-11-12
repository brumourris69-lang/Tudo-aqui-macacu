import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';
import 'package:tudo_aqui_macacu/features/events/models/public_event.dart';
import 'package:tudo_aqui_macacu/features/events/pages/event_detail_page.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_config.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_overview.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const _captureKey = ValueKey<String>('public-area-visual-capture');

// ignore: subtype_of_sealed_class
class _DocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _business = Business.fromData('fixture-business', {
  'name': 'Café da Serra',
  'category': 'Alimentação',
  'subcategory': 'Cafés',
  'shortDescription': 'Cafés e quitutes locais.',
  'location': 'Centro, Cachoeiras de Macacu',
  'phone': '+55 (21) 99999-1234',
  'instagram': 'cafedaserra',
  'maps': 'https://maps.example.invalid/cafe',
  'videoUrls': ['https://youtube.com/watch?v=fixture'],
  'listingTier': 'premium',
  'premiumUntil': DateTime.utc(2099),
});

final _tourismConfig = <String, dynamic>{
  'title': 'Explore Macacu',
  'subtitle': 'Natureza, memória e experiências locais.',
  'categories': {
    'pontos_turisticos': {'description': 'Lugares para conhecer.'},
    'trilhas': {'description': 'Caminhos e paisagens.'},
    'guias_turisticos': {'description': 'Orientação local.'},
    'historia_cidade': {'description': 'Memórias da cidade.'},
  },
};

final _tourismSnapshot = PublicContentSnapshot([
  for (final (id, title, category) in [
    ('spot-1', 'Cachoeira de teste', 'pontos_turisticos'),
    ('trail-1', 'Trilha de teste', 'trilhas'),
    ('guide-1', 'Guia de teste', 'guias_turisticos'),
    ('history-1', 'Memória de teste', 'historia_cidade'),
  ])
    PublicContentDocument(id, {
      'title': title,
      'category': category,
      'published': true,
      'active': true,
    }, _DocumentReference()),
]);

final _utilities = <UtilityItem>[
  const UtilityItem(
    id: 'phones',
    name: 'Telefones úteis',
    iconKey: 'phone',
    description: 'Contatos públicos cadastrados.',
    destinationType: 'internal',
    destination: 'usefulPhones',
    order: 1,
    category: 'Serviços públicos',
  ),
  const UtilityItem(
    id: 'transport',
    name: 'Transporte',
    iconKey: 'bus',
    description: 'Linhas e informações locais.',
    destinationType: 'internal',
    destination: 'transport',
    order: 2,
    category: 'Mobilidade',
  ),
];

final _eventData = <String, dynamic>{
  'title': 'Encontro cultural de teste',
  'description': 'Programação pública sintética para revisão visual.',
  'category': 'Cultura',
  'eventDate': '2030-06-15T18:00:00.000',
  'startTime': '18:00',
  'endTime': '21:00',
  'location': 'Praça de teste',
  'published': true,
  'active': true,
};

PublicContentSnapshot _eventSnapshot() => PublicContentSnapshot([
  PublicContentDocument('fixture-event', _eventData, _DocumentReference()),
]);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final poppins = FontLoader('Poppins')
      ..addFont(_localFont('Poppins-Regular.ttf'))
      ..addFont(_localFont('Poppins-Medium.ttf'))
      ..addFont(_localFont('Poppins-SemiBold.ttf'))
      ..addFont(_localFont('Poppins-Bold.ttf'));
    await poppins.load();
    final iconFont = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(iconFont))).load();
  });

  testWidgets('captures the public areas with the shared design system', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await _capture(
      tester,
      name: 'estabelecimentos-lista',
      size: const Size(360, 900),
      child: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BusinessCard(
              business: _business,
              saved: false,
              onFavorite: () {},
              onOpen: () {},
              onViewBusiness: () {},
              onWhatsApp: () {},
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      name: 'estabelecimento-detalhe',
      size: const Size(360, 1200),
      child: BusinessProfile(
        business: _business,
        saved: false,
        onFavorite: () {},
        trackShareMetric: false,
      ),
    );
    expect(find.byKey(const ValueKey('business-actions-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      name: 'explorar-macacu',
      size: const Size(360, 1500),
      compareGolden: BetaEnvironment.enabled,
      child: TourismHomeView(
        routesStreamFactory: () => Stream.value(_tourismSnapshot),
        configStreamFactory: () => Stream.value(_tourismConfig),
        adminOverride: false,
      ),
    );
    expect(find.text('Pontos turísticos'), findsOneWidget);
    expect(find.text('Trilhas'), findsOneWidget);
    expect(find.text('Guias turísticos'), findsOneWidget);
    expect(find.text('História da cidade'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tourism-global-search')),
      BetaEnvironment.enabled ? findsNothing : findsOneWidget,
      reason: 'a busca global é indisponível somente na variante Beta',
    );
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      name: 'utilidades-da-cidade',
      size: const Size(360, 1100),
      child: ResourcesHub(
        utilitiesStreamFactory: () => Stream.value(_utilities),
      ),
    );
    expect(find.text('Telefones úteis'), findsWidgets);
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      name: 'eventos-da-cidade',
      size: const Size(360, 1200),
      child: CityAgendaView(
        eventsStreamFactory: () => Stream.value(_eventSnapshot()),
      ),
    );
    expect(find.text('Encontro cultural de teste'), findsOneWidget);
    expect(find.textContaining('15/06/2030'), findsWidgets);
    expect(find.textContaining('15/06/2030 às 18:00'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      name: 'detalhe-do-evento',
      size: const Size(360, 1100),
      child: EventDetailPage(
        eventId: 'fixture-event',
        resolveEvent: (_) async =>
            PublicEvent.fromMap({..._eventData, 'id': 'fixture-event'}),
        onToggleAgenda: (_) async => true,
      ),
    );
    expect(find.text('Data e horário'), findsOneWidget);
    expect(find.textContaining('15/06/2030'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public area widgets fit small phones and enlarged text', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final spot = TouristSpot.fromData('fixture-spot', const {
      'title': 'Ponto turístico com nome longo para validar o cartão',
      'category': 'pontos_turisticos',
      'location': 'Localização com endereço longo em Cachoeiras de Macacu',
      'description': 'Descrição de teste para validação de conteúdo público.',
    });

    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.5]) {
        await _pumpResponsive(
          tester,
          width: width,
          scale: scale,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              BusinessCard(
                business: _business,
                saved: false,
                onFavorite: () {},
                onOpen: () {},
                onViewBusiness: () {},
                onWhatsApp: () {},
              ),
              const SizedBox(height: 12),
              TouristSpotCard(spot: spot),
              const SizedBox(height: 12),
              TourismOverview(
                config: TourismConfig.fromMap(_tourismConfig),
                admin: false,
                onCategoryTap: (_) {},
              ),
            ],
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'turismo e comércios: $width / $scale',
        );

        await _pumpResponsive(
          tester,
          width: width,
          scale: scale,
          child: ResourcesHub(
            utilitiesStreamFactory: () => Stream.value(_utilities),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'utilidades: $width / $scale',
        );

        await _pumpResponsive(
          tester,
          width: width,
          scale: scale,
          child: CityAgendaView(
            eventsStreamFactory: () => Stream.value(_eventSnapshot()),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'eventos: $width / $scale',
        );

        await _pumpResponsive(
          tester,
          width: width,
          scale: scale,
          child: BusinessProfile(
            business: _business,
            saved: false,
            onFavorite: () {},
            trackShareMetric: false,
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'detalhe do comércio: $width / $scale',
        );

        await _pumpResponsive(
          tester,
          width: width,
          scale: scale,
          child: EventDetailPage(
            eventId: 'fixture-event',
            resolveEvent: (_) async =>
                PublicEvent.fromMap({..._eventData, 'id': 'fixture-event'}),
            onToggleAgenda: (_) async => true,
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'detalhe do evento: $width / $scale',
        );
      }
    }
  });
}

Future<ByteData> _localFont(String name) async => ByteData.sublistView(
  await File('assets/fonts/local-poppins/$name').readAsBytes(),
);

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
  bool compareGolden = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, app) => RepaintBoundary(key: _captureKey, child: app!),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byKey(_captureKey));
  final assetProviders = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .whereType<AssetImage>()
      .toSet();
  for (final provider in assetProviders) {
    await tester.runAsync(() => precacheImage(provider, context));
  }
  await tester.pumpAndSettle();
  if (compareGolden) {
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('goldens/public_areas/$name.png'),
    );
  }
}

Future<void> _pumpResponsive(
  WidgetTester tester, {
  required double width,
  required double scale,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}
