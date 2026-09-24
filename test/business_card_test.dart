import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_avatar.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';

void main() {
  const business = Business(
    'Estúdio Raiz',
    'Beleza',
    'Cabeleireiros e salões',
    'Cuidado, beleza e autoestima para você.',
    'Centro · Cachoeiras de Macacu',
    12,
    featured: true,
    open: true,
  );

  testWidgets('BusinessCard exibe dados principais e avatar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCard(
            business: business,
            saved: false,
            onFavorite: () {},
            onOpen: () {},
            onViewBusiness: () {},
            onWhatsApp: () {},
          ),
        ),
      ),
    );

    expect(find.text('Estúdio Raiz'), findsOneWidget);
    expect(find.text('Cabeleireiros e salões'), findsOneWidget);
    expect(find.text('DESTAQUE'), findsOneWidget);
    expect(find.text('ABERTO'), findsOneWidget);
    expect(find.byType(BusinessAvatar), findsOneWidget);
  });

  testWidgets('BusinessCard dispara callbacks corretos', (tester) async {
    var openCount = 0;
    var viewCount = 0;
    var whatsappCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCard(
            business: business,
            saved: false,
            onFavorite: () {},
            onOpen: () => openCount++,
            onViewBusiness: () => viewCount++,
            onWhatsApp: () => whatsappCount++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(BusinessCard));
    await tester.tap(find.text('Ver negócio'));
    await tester.tap(find.text('WhatsApp'));

    expect(openCount, 1);
    expect(viewCount, 1);
    expect(whatsappCount, 1);
  });
}
