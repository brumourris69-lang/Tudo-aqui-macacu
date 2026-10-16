import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/widgets/staging_environment_banner.dart';

void main() {
  testWidgets('staging banner clearly identifies test environment', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StagingEnvironmentBanner())),
    );

    expect(find.text('HOMOLOGAÇÃO · DADOS DE TESTE'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Aplicativo conectado ao ambiente de homologação'),
      findsOneWidget,
    );
  });
}
