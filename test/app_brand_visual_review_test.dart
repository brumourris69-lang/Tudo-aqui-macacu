import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/core/models/weather_data.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/core/widgets/app_brand.dart';
import 'package:tudo_aqui_macacu/core/services/weather_service.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/establishment_listing_level.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart' show WelcomeHero;

const _captureKey = ValueKey<String>('identity-preview-capture');

final _sampleBusiness = Business(
  'Café Macacu',
  'Onde comer?',
  'Cafeterias',
  'Café, quitutes e produtos da nossa cidade.',
  'Centro · Cachoeiras de Macacu',
  12,
  phone: '(21) 99999-0000',
  whatsapp: '(21) 98888-0000',
  instagram: '@cafemacacu',
  maps: 'https://maps.google.com/?q=Cachoeiras+de+Macacu',
  videoUrls: ['https://youtu.be/example'],
  listingTier: ListingTier.premium,
  premiumUntil: DateTime.utc(2099),
);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await rootBundle.load('assets/images/tudo-aqui-macacu-icon-v1.png');
    final poppins = FontLoader('Poppins')
      ..addFont(_loadLocalFont('Poppins-Regular.ttf'))
      ..addFont(_loadLocalFont('Poppins-Medium.ttf'))
      ..addFont(_loadLocalFont('Poppins-SemiBold.ttf'))
      ..addFont(_loadLocalFont('Poppins-Bold.ttf'));
    await poppins.load();
    final iconFont = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(iconFont));
    await loader.load();
  });

  testWidgets('AppBrand variants match the reviewed identity snapshot', (
    tester,
  ) async {
    await _capture(
      tester,
      name: 'marca-variantes-320',
      size: const Size(320, 560),
      child: const _BrandVariantsPreview(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('gera prévias da marca e cabeçalhos em larguras comuns', (
    tester,
  ) async {
    // Warm asynchronous local images before comparing actual brand previews.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 460);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WelcomeHero(
              onSearch: _noOp,
              user: null,
              config: HomePageConfig.fromMap(const {}),
              weatherService: _PreviewWeatherService(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _precacheHomeBackground(tester);
    await _precacheVisibleAssetImages(tester);
    await tester.pump(const Duration(milliseconds: 200));

    for (final width in [320.0, 360.0, 412.0]) {
      final header = Scaffold(
        body: SingleChildScrollView(
          child: WelcomeHero(
            onSearch: _noOp,
            user: null,
            config: HomePageConfig.fromMap(const {}),
            weatherService: _PreviewWeatherService(),
          ),
        ),
      );
      if (BetaEnvironment.enabled) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 460);
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: header),
        );
        await tester.pump();
        await _precacheVisibleAssetImages(tester);
        expect(find.byType(AppBrand), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'largura $width');
      } else {
        await _capture(
          tester,
          name: 'home-cabecalho-${width.toInt()}',
          size: Size(width, 460),
          child: header,
        );
      }

      await _capture(
        tester,
        name: 'estabelecimento-${width.toInt()}',
        size: Size(width, 900),
        child: BusinessProfile(
          business: _sampleBusiness,
          saved: false,
          onFavorite: _noOp,
          canEdit: true,
          onEdit: _noOp,
          trackShareMetric: false,
        ),
      );
    }

    await _capture(
      tester,
      name: 'estabelecimento-320-texto-ampliado',
      size: const Size(320, 900),
      textScale: 1.5,
      child: BusinessProfile(
        business: _sampleBusiness,
        saved: false,
        onFavorite: _noOp,
        canEdit: true,
        onEdit: _noOp,
        trackShareMetric: false,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

void _noOp() {}

Future<ByteData> _loadLocalFont(String fileName) async => ByteData.sublistView(
  await File('assets/fonts/local-poppins/$fileName').readAsBytes(),
);

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: _captureKey, child: app!),
      ),
      home: child,
    ),
  );
  await tester.pump();
  await _precacheHomeBackground(tester);
  await _precacheVisibleAssetImages(tester);
  // Home includes an auto-advancing weather chip, so settle a fixed number of
  // frames instead of waiting for all repeating animations to stop.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('goldens/visual_identity/$name.png'),
  );
}

Future<void> _precacheHomeBackground(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(
    () =>
        precacheImage(const AssetImage(homeWaterfallBackgroundAsset), context),
  );
}

Future<void> _precacheVisibleAssetImages(WidgetTester tester) async {
  final images = find.byType(Image).evaluate().where((element) {
    final widget = element.widget as Image;
    return widget.image is AssetImage;
  }).toList();
  await tester.runAsync(() async {
    for (final element in images) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pump();
}

class _PreviewWeatherService extends WeatherService {
  @override
  Future<WeatherData> load() async => WeatherData(
    temperature: 24,
    feelsLike: 24,
    humidity: 70,
    precipitation: 0,
    weatherCode: 0,
    windSpeed: 4,
    maximum: 28,
    minimum: 19,
    rainChance: 10,
    dailyWeatherCode: 0,
    updatedAt: DateTime.now().toUtc(),
  );
}

class _BrandVariantsPreview extends StatelessWidget {
  const _BrandVariantsPreview();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.soft,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Marca clara', style: Theme.of(context).textTheme.titleSmall),
          const Card(
            child: Padding(padding: EdgeInsets.all(16), child: AppBrand()),
          ),
          const SizedBox(height: 12),
          Text('Marca inversa', style: Theme.of(context).textTheme.titleSmall),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
            ),
            child: const AppBrand(inverse: true),
          ),
          const SizedBox(height: 12),
          Text('Marca compacta', style: Theme.of(context).textTheme.titleSmall),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: AppBrand(compact: true),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TextField(
                    decoration: InputDecoration(labelText: 'Campo'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Botão do tema'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
