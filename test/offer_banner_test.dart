import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('offer artwork and existing text fit mobile widths', (tester) async {
    for (final width in [320.0, 390.0, 480.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width - 36,
                child: const OfferBanner(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(tester.getSize(find.byType(OfferBanner)).width, width - 36);
      expect(find.text('OFERTA EM DESTAQUE'), findsOneWidget);
      expect(find.text('Condições especiais para a cidade.'), findsOneWidget);
      expect(find.text('Confira os detalhes no negócio participante.'), findsOneWidget);
    }
  });
}
