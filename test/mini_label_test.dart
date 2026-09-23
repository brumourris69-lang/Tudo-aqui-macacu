import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/widgets/mini_label.dart';

void main() {
  testWidgets('MiniLabel exibe texto com a cor informada', (tester) async {
    const labelColor = Color(0xFFFF7A00);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MiniLabel(text: 'DESTAQUE', color: labelColor),
        ),
      ),
    );

    expect(find.text('DESTAQUE'), findsOneWidget);

    final text = tester.widget<Text>(find.text('DESTAQUE'));
    expect(text.style?.color, labelColor);
    expect(text.style?.fontWeight, FontWeight.w800);
  });
}
