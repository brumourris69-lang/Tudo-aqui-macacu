import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/core/auth/admin_authorization.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/core/content/public_content_repository.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/core/widgets/app_bottom_navigation_bar.dart';
import 'package:tudo_aqui_macacu/features/home/models/home_page_config.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

import 'support/weather_fixture.dart';

const _captureKey = ValueKey<String>('home-visual-review-capture');
final _previewConfiguration = <String, dynamic>{
  'heroTitle': 'Descubra Macacu',
  'sections': {
    for (final section in defaultHomeOrder) section: false,
    'categories': true,
  },
  'sectionOrder': <String>['categories'],
  'visual': {'backgroundType': 'image'},
};

class _PreviewAdminUser implements User {
  @override
  bool get isAnonymous => false;

  @override
  String get uid => 'home-visual-admin-fixture';

  @override
  String? get displayName => 'Admin';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('visual fixture hides data sections while retaining Home shortcuts', () {
    final config = HomePageConfig.fromMap(_previewConfiguration);
    expect(config.enabled('banner'), isFalse);
    expect(config.enabled('categories'), isTrue);
  });

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
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

  testWidgets('captures visitor Home at 320, 360 and 412 px', (tester) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    // Warm local assets without comparing the warm-up frame to a golden:
    // this frame exists only to wait for asynchronous image decoding.
    await _warmHomeAssets(tester);
    for (final width in [320.0, 360.0, 412.0]) {
      await _capture(
        tester,
        name: 'home-visitante-${width.toInt()}',
        size: Size(width, 900),
        child: _home(),
        compareGolden: BetaEnvironment.enabled,
      );
      expect(
        find.text('Buscar comércios, serviços e mais'),
        BetaEnvironment.enabled ? findsNothing : findsOneWidget,
        reason: 'a busca global só fica oculta na variante Beta',
      );
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });

  testWidgets('captures Home with Admin editing controls visible', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    final authorization = AdminAuthorization()
      ..value = const AdminClaimState(
        uid: 'home-visual-admin-fixture',
        allowed: true,
      );
    addTearDown(authorization.dispose);

    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AdminAuthorizationScope(
        authorization: authorization,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, app) =>
              RepaintBoundary(key: _captureKey, child: app!),
          home: _home(user: _PreviewAdminUser()),
        ),
      ),
    );
    await _precacheHomeBackground(tester);
    await _precacheVisibleAssetImages(tester);
    await tester.pump();
    await _pumpHomeFrames(tester);
    await tester.tap(find.byTooltip('Editar Home'));
    await _pumpHomeFrames(tester);

    expect(find.text('Edição Admin ativa'), findsOneWidget);
    expect(find.byTooltip('Editar seções'), findsOneWidget);
    if (BetaEnvironment.enabled) {
      await _expectGolden(tester, 'home-admin-editando');
    } else {
      expect(find.text('Buscar comércios, serviços e mais'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('captures main navigation at common phone widths', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    for (final width in [320.0, 360.0, 412.0]) {
      await _capture(
        tester,
        name: 'navegacao-${width.toInt()}',
        size: Size(width, 900),
        child: Scaffold(
          body: const Center(child: Text('Navegação principal')),
          bottomNavigationBar: AppBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(5),
      );
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });

  testWidgets('Home remains readable with enlarged text on a narrow screen', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await _capture(
      tester,
      name: 'home-visitante-texto-ampliado-320',
      size: const Size(320, 900),
      textScale: 1.5,
      child: _home(),
      compareGolden: BetaEnvironment.enabled,
    );
    if (!BetaEnvironment.enabled) {
      expect(find.text('Buscar comércios, serviços e mais'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation labels remain visible with enlarged text', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await _capture(
      tester,
      name: 'navegacao-texto-ampliado-320',
      size: const Size(320, 900),
      textScale: 1.5,
      child: Scaffold(
        body: const Center(child: Text('Navegação principal')),
        bottomNavigationBar: AppBottomNavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    expect(
      NavigationBarTheme.of(tester.element(find.byType(NavigationBar))).height,
      96,
    );
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Utilidades'), findsOneWidget);
    expect(tester.getSize(find.text('Utilidades')).height, lessThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'banner uses the existing empty-state artwork with a local feed',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      Widget banner() => Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: AdCarousel(
            adsSnapshotStreamFactory: () =>
                Stream.value(PublicContentSnapshot(const [])),
            businessesSnapshotStreamFactory: () =>
                Stream.value(PublicContentSnapshot(const [])),
          ),
        ),
      );
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, app) =>
              RepaintBoundary(key: _captureKey, child: app!),
          home: banner(),
        ),
      );
      await _pumpHomeFrames(tester);
      final bannerImage = tester.widget<Image>(find.byType(Image));
      await tester.runAsync(
        () => precacheImage(
          bannerImage.image,
          tester.element(find.byType(Image)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Image), findsOneWidget);
      expect(tester.getSize(find.byType(Image)).height, greaterThan(0));
      await _expectGolden(tester, 'home-banner-vazio');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ByteData> _loadLocalFont(String fileName) async => ByteData.sublistView(
  await File('assets/fonts/local-poppins/$fileName').readAsBytes(),
);

Widget _home({User? user}) => Scaffold(
  body: HomeView(
    saved: const <String>{},
    favorite: (_) {},
    showExplore: () {},
    user: user,
    configurationStreamFactory: _previewConfigurationStream,
    weatherService: unavailableWeather(),
  ),
);

Stream<Map<String, dynamic>> _previewConfigurationStream() {
  return Stream.value(_previewConfiguration);
}

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Widget child,
  double textScale = 1,
  bool compareGolden = true,
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
  await _pumpHomeFrames(tester);
  if (compareGolden) await _expectGolden(tester, name);
}

Future<void> _warmHomeAssets(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 900);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: _home()));
  await tester.pump();
  await _precacheHomeBackground(tester);
  await _precacheVisibleAssetImages(tester);
  await _pumpHomeFrames(tester);
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

Future<void> _pumpHomeFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byKey(_captureKey),
  matchesGoldenFile('goldens/home_identity/$name.png'),
);
