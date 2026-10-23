import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';

void main() {
  testWidgets('favorite action has a business-specific tooltip', (
    tester,
  ) async {
    const business = Business(
      'Mercado Macacu',
      'Comércio',
      'Mercados',
      '',
      'Centro',
      0,
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

  testWidgets('WhatsApp action requires an available valid public contact', (
    tester,
  ) async {
    var whatsappTaps = 0;
    Future<void> pumpCard(String whatsapp) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCard(
            business: Business(
              'Mercado Macacu',
              'Comércio',
              'Mercados',
              '',
              'Centro',
              0,
              whatsapp: whatsapp,
            ),
            saved: false,
            onFavorite: () {},
            onOpen: () {},
            onViewBusiness: () {},
            onWhatsApp: () => whatsappTaps++,
          ),
        ),
      ),
    );

    await pumpCard('');
    expect(find.text('WhatsApp'), findsNothing);

    await pumpCard('not a valid contact');
    expect(find.text('WhatsApp'), findsNothing);

    await pumpCard('https://example.com/contact');
    expect(find.text('WhatsApp'), findsNothing);

    await pumpCard('https://wa.me/1234567');
    expect(find.text('WhatsApp'), findsNothing);

    await pumpCard('https://wa.me/5521999999999');
    expect(find.text('WhatsApp'), findsOneWidget);
    await tester.tap(find.text('WhatsApp'));
    expect(whatsappTaps, 1);

    await pumpCard('+55 (21) 99999-9999');
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets(
    'card does not infer a reported open or closed status for legacy data',
    (tester) async {
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
    },
  );

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
    expect(
      find.byTooltip('Remover dos favoritos Loja fechada'),
      findsOneWidget,
    );
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
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

  testWidgets('featured name can wrap to two lines before truncation', (
    tester,
  ) async {
    const name = 'Estabelecimento fictício 01';
    const business = Business(
      name,
      'Comércio',
      'Mercados',
      'Descrição curta.',
      'Centro',
      0,
      featured: true,
    );

    await tester.binding.setSurfaceSize(const Size(320, 720));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: SizedBox(
                width: 292,
                child: BusinessCard(
                  business: business,
                  saved: false,
                  onFavorite: () {},
                  onOpen: () {},
                  onViewBusiness: () {},
                  onWhatsApp: () {},
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.maxLines, 2);
    expect(paragraph.size.height, greaterThan(20));
    expect(
      tester.widget<Text>(find.text(name)).overflow,
      TextOverflow.ellipsis,
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('featured card avoids overflow across viewport and text scales', (
    tester,
  ) async {
    const business = Business(
      'Estabelecimento fictício 01 com um nome muito longo para leitura',
      'Comércio',
      'Mercados',
      'Descrição longa que deve continuar limitada e não ultrapassar a altura do cartão.',
      'Centro, Cachoeiras de Macacu',
      0,
      featured: true,
    );

    for (final width in [320.0, 360.0, 393.0, 480.0]) {
      for (final textScale in [1.0, 1.5]) {
        await tester.binding.setSurfaceSize(Size(width, 720));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 292,
                    child: BusinessCard(
                      business: business,
                      saved: false,
                      onFavorite: () {},
                      onOpen: () {},
                      onViewBusiness: () {},
                      onWhatsApp: () {},
                      compact: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (textScale > 1) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(business.name),
          );
          expect(paragraph.maxLines, 2);
          expect(paragraph.didExceedMaxLines, isTrue);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'viewport $width dp, text scale $textScale',
        );
      }
    }

    await tester.binding.setSurfaceSize(null);
  });
}
