import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';

void main() {
  testWidgets('favorite action has a business-specific tooltip', (tester) async {
    const business = Business(
      'Mercado Macacu', 'Comércio', 'Mercados', '', 'Centro', 0,
    );
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

    expect(find.byTooltip('Favoritar Mercado Macacu'), findsOneWidget);
  });

  testWidgets('card does not infer a reported open or closed status for legacy data', (
    tester,
  ) async {
    final legacy = Business.fromData('legacy', const {'name': 'Loja antiga'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCard(
            business: legacy,
            saved: false,
            onFavorite: () {},
            onOpen: () {},
            onViewBusiness: () {},
            onWhatsApp: () {},
          ),
        ),
      ),
    );

    expect(find.text('Status informado: aberto'), findsNothing);
    expect(find.text('Status informado: fechado'), findsNothing);
    expect(find.text('ABERTO'), findsNothing);
  });

  testWidgets('card uses the same wording as profile for explicit status', (
    tester,
  ) async {
    final closed = Business.fromData('closed', const {
      'name': 'Loja fechada',
      'open': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCard(
            business: closed,
            saved: true,
            onFavorite: () {},
            onOpen: () {},
            onViewBusiness: () {},
            onWhatsApp: () {},
          ),
        ),
      ),
    );

    expect(find.text('Status informado: fechado'), findsOneWidget);
    expect(find.byTooltip('Remover dos favoritos Loja fechada'), findsOneWidget);
  });

  testWidgets('card lays out without overflow at narrow widths and larger text', (
    tester,
  ) async {
    const business = Business(
      'Estabelecimento com nome longo para testar responsividade',
      'Comércio',
      'Categoria com nome longo',
      'Descrição extensa para confirmar que o cartão continua utilizável com escala de texto maior.',
      'Endereço muito comprido, Centro, Cachoeiras de Macacu',
      0,
    );

    for (final width in [320.0, 360.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BusinessCard(
                business: business,
                saved: false,
                onFavorite: () {},
                onOpen: () {},
                onViewBusiness: () {},
                onWhatsApp: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    await tester.binding.setSurfaceSize(null);
  });
}
