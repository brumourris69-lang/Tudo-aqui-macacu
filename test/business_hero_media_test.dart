import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_colors.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_hero_media.dart';

void main() {
  const baseBusiness = Business(
    'Estúdio Raiz',
    'Beleza',
    'Cabeleireiros e salões',
    'Cuidado, beleza e autoestima para você.',
    'Centro',
    12,
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('BusinessHeroMedia usa gradiente quando não há mídia', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const BusinessHeroMedia(business: baseBusiness)),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;

    expect(gradient.colors, [AppColors.ocean, AppColors.sky]);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('BusinessHeroMedia usa asset de turismo sem mídia', (
    tester,
  ) async {
    const tourism = Business(
      'Cachoeira',
      'Turismo',
      'Cachoeiras',
      'Explore lugares com água.',
      'Macacu',
      5,
    );

    await tester.pumpWidget(wrap(const BusinessHeroMedia(business: tourism)));

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/macacu-waterfall-hero.png',
    );
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('BusinessHeroMedia exibe indicadores com múltiplas imagens', (
    tester,
  ) async {
    const withGallery = Business(
      'Estúdio Raiz',
      'Beleza',
      'Cabeleireiros e salões',
      'Cuidado, beleza e autoestima para você.',
      'Centro',
      12,
      galleryUrls: [
        'https://example.com/one.png',
        'https://example.com/two.png',
      ],
    );

    await tester.pumpWidget(
      wrap(const BusinessHeroMedia(business: withGallery)),
    );

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNWidgets(2));
  });
}
