import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/establishment_listing_level.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';

const _captureKey = ValueKey<String>('business-profile-redesign-capture');
final _business = Business(
  'Café da Serra',
  'Alimentação',
  'Cafés',
  'Cafés e quitutes locais.',
  'Centro, Cachoeiras de Macacu',
  12,
  phone: '(21) 99999-0000',
  instagram: '@cafedaserra',
  maps: 'https://maps.example.invalid/cafe',
  videoUrls: ['https://youtube.com/watch?v=fixture'],
  statusSpecified: false,
  listingTier: ListingTier.premium,
  premiumUntil: DateTime.utc(2099),
);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final poppins = FontLoader('Poppins')
      ..addFont(_localFont('Poppins-Regular.ttf'))
      ..addFont(_localFont('Poppins-Medium.ttf'))
      ..addFont(_localFont('Poppins-SemiBold.ttf'))
      ..addFont(_localFont('Poppins-Bold.ttf'));
    await poppins.load();
    final materialIcons = await rootBundle.load(
      'fonts/MaterialIcons-Regular.otf',
    );
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(materialIcons))).load();
  });

  testWidgets('redesign se adapta e cria prévias reais para revisão', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    Future<void> render({
      required double width,
      double textScale = 1,
      String? captureName,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1200);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => RepaintBoundary(
            key: _captureKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          home: BusinessProfile(
            business: _business,
            saved: false,
            onFavorite: () {},
            trackShareMetric: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Café da Serra'), findsOneWidget);
      expect(find.text('Contato e acesso'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: '$width px, escala $textScale',
      );
      if (captureName != null) {
        await expectLater(
          find.byKey(_captureKey),
          matchesGoldenFile('goldens/redesign_review/$captureName.png'),
        );
      }
    }

    for (final width in [320.0, 360.0, 412.0]) {
      await render(
        width: width,
        captureName: 'estabelecimento-${width.toInt()}-depois',
      );
    }
    await render(
      width: 320,
      textScale: 1.5,
      captureName: 'estabelecimento-320-texto-ampliado-depois',
    );
    await render(width: 320, textScale: 2);
  });
}

Future<ByteData> _localFont(String fileName) async => ByteData.sublistView(
  await File('assets/fonts/local-poppins/$fileName').readAsBytes(),
);
