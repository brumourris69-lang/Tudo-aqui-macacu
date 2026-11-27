import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/utilities/models/utility_item.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final fonts = FontLoader('Poppins')
      ..addFont(_loadFont('Poppins-Regular.ttf'))
      ..addFont(_loadFont('Poppins-Medium.ttf'))
      ..addFont(_loadFont('Poppins-SemiBold.ttf'))
      ..addFont(_loadFont('Poppins-Bold.ttf'));
    await fonts.load();
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(icons))).load();
  });

  testWidgets('Correios tracking utility card displays the official logo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: Color(0xFFF4F7FB),
          body: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: UtilityCard(
                item: UtilityItem(
                  id: 'correiosTracking',
                  name: 'Rastreamento dos Correios',
                  iconKey: 'mail',
                  description:
                      'Acompanhe suas encomendas pelo código de rastreio',
                  destinationType: 'url',
                  destination:
                      'https://rastreamento.correios.com.br/app/index.php',
                  order: 70,
                  category: 'Serviços digitais',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/utility-logo-correios.png'),
        tester.element(find.byType(CorreiosLogoBadge)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.byType(CorreiosLogoBadge), findsOneWidget);
    await expectLater(
      find.byType(UtilityCard),
      matchesGoldenFile('goldens/correios_tracking_utility_card.png'),
    );
    for (final width in [320.0, 360.0, 412.0]) {
      tester.view.physicalSize = Size(width, 180);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });
}

Future<ByteData> _loadFont(String name) async => File(
  'assets/fonts/local-poppins/$name',
).readAsBytes().then((bytes) => ByteData.sublistView(bytes));
