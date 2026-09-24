import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/widgets/sprite.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_avatar.dart';

void main() {
  const business = Business(
    'Estúdio Raiz',
    'Beleza',
    'Cabeleireiros e salões',
    'Cuidado, beleza e autoestima para você.',
    'Centro',
    12,
  );

  testWidgets(
    'BusinessAvatar usa fallback com Sprite quando logoUrl está vazio',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BusinessAvatar(business: business, size: 50)),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, 50);
      expect(container.constraints?.maxHeight, 50);
      expect(find.byType(Sprite), findsOneWidget);
    },
  );

  testWidgets('BusinessAvatar renderiza imagem de rede quando logoUrl existe', (
    tester,
  ) async {
    const withLogo = Business(
      'Estúdio Raiz',
      'Beleza',
      'Cabeleireiros e salões',
      'Cuidado, beleza e autoestima para você.',
      'Centro',
      12,
      logoUrl: 'https://res.cloudinary.com/demo/image/upload/logo.png',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BusinessAvatar(business: withLogo)),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
  });
}
