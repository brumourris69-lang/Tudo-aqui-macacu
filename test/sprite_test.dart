import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/widgets/sprite.dart';

void main() {
  testWidgets('Sprite renderiza o asset legado correspondente ao índice', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Sprite(index: 0, size: 72))),
    );

    final box = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(box.width, 72);
    expect(box.height, 72);

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/icons/01_comercio.png',
    );
    expect(image.width, 72);
    expect(image.height, 72);
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('Sprite usa serviços como fallback para índice inválido', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Sprite(index: 999))),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/icons/03_servicos.png',
    );
  });
}
