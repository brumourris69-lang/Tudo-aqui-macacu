import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/services/external_link_service.dart';

void main() {
  testWidgets('telefone exige confirmação antes de iniciar a ligação', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openUrl(context, 'tel:+5521999999999', 'Ligação'),
              child: const Text('Abrir telefone'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir telefone'));
    await tester.pumpAndSettle();
    expect(find.text('Ligar para este estabelecimento?'), findsOneWidget);
    expect(find.text('O telefone informado é +5521999999999.'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Ligar para este estabelecimento?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('telefone inválido não apresenta opção de confirmação', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openUrl(context, 'tel:123', 'Ligação'),
              child: const Text('Abrir telefone'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir telefone'));
    await tester.pumpAndSettle();
    expect(find.text('O link de Ligação não é permitido.'), findsOneWidget);
    expect(find.text('Ligar para este estabelecimento?'), findsNothing);
  });
}
