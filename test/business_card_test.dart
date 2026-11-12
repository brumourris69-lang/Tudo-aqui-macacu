import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/establishment_listing_level.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/published_business_strip.dart';

void main() {
  testWidgets('Basic card never shows commercial media or contact actions', (
    tester,
  ) async {
    final basic = Business.fromBasicProjection('basic-card', const {
      'name': 'Padaria Básica',
      'category': 'Comércio',
      'address': 'Centro',
      'phone': '2222-3333',
      'description': 'Descrição Premium',
      'imageUrl': 'https://example.test/private-card.jpg',
      'whatsapp': '5521999999999',
      'hours': 'Sempre aberta',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessCard(
            business: basic,
            saved: false,
            onFavorite: () {},
            onOpen: () {},
            onViewBusiness: () {},
            onWhatsApp: () {},
          ),
        ),
      ),
    );

    expect(find.text('Padaria Básica'), findsOneWidget);
    expect(find.text('Comércio'), findsOneWidget);
    expect(find.text('Descrição Premium'), findsNothing);
    expect(find.text('WhatsApp'), findsNothing);
    expect(
      find.byKey(const ValueKey('business-card-cover-Padaria Básica')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('public business card exposes a share action when supplied', (
    tester,
  ) async {
    var shares = 0;
    final business = Business(
      'Mercado Macacu',
      'Comércio',
      '',
      'Descrição pública.',
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
            onShare: () async => shares++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Compartilhar Mercado Macacu'), findsOneWidget);
    await tester.tap(find.byTooltip('Compartilhar Mercado Macacu'));
    await tester.pump();
    expect(shares, 1);
  });

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
    expect(find.text('Comércio · Mercados'), findsOneWidget);
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
              listingTier: ListingTier.premium,
              premiumUntil: DateTime.utc(2099),
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
    final closed = Business.fromData('closed', {
      'name': 'Loja fechada',
      'open': false,
      'listingTier': 'premium',
      'premiumUntil': DateTime.utc(2099),
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

  testWidgets('Home showcase adapts its card width to common phone sizes', (
    tester,
  ) async {
    final business = Business(
      'Café da Serra',
      'Alimentação',
      'Cafés especiais',
      'Cafés locais.',
      'Centro de Cachoeiras de Macacu',
      12,
      featured: true,
      listingTier: ListingTier.premium,
      premiumUntil: DateTime.utc(2099),
    );

    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 760));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PublishedBusinessStrip(
              saved: const {},
              favorite: (_) {},
              businessesStreamFactory: () => Stream.value([business]),
              cardBuilder: (context, item, saved, onFavorite) => BusinessCard(
                business: item,
                saved: saved,
                onFavorite: onFavorite,
                onOpen: () {},
                onViewBusiness: () {},
                onWhatsApp: () {},
                onShare: () async {},
                compact: true,
                featuredShowcase: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final size = tester.getSize(
        find.byKey(const ValueKey('featured-business-showcase-card')),
      );
      final coverSize = tester.getSize(
        find.byKey(const ValueKey('featured-business-cover')),
      );
      expect(size.width, width == 320 ? 280 : 290);
      expect(size.height, greaterThan(250));
      expect(size.height, lessThan(350));
      expect(coverSize.height, greaterThanOrEqualTo(148));
      expect(find.text('DESTAQUE'), findsOneWidget);
      expect(find.text('Alimentação · Cafés especiais'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'Home showcase handles long text with enlarged accessibility text',
    (tester) async {
      const business = Business(
        'Estabelecimento com um nome comprido para testar a vitrine',
        'Serviços',
        'Categoria secundária com descrição extensa',
        'Uma descrição longa que não deve ocupar espaço demais na vitrine.',
        'Estrada do Centro, Cachoeiras de Macacu, Rio de Janeiro',
        2,
        featured: true,
      );

      for (final width in [320.0, 360.0, 412.0]) {
        for (final textScale in [1.5, 2.0]) {
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
                body: PublishedBusinessStrip(
                  saved: const {},
                  favorite: (_) {},
                  businessesStreamFactory: () => Stream.value(const [business]),
                  cardBuilder: (context, item, saved, onFavorite) =>
                      BusinessCard(
                        business: item,
                        saved: saved,
                        onFavorite: onFavorite,
                        onOpen: () {},
                        onViewBusiness: () {},
                        onWhatsApp: () {},
                        featuredShowcase: true,
                      ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('featured-business-showcase-card')),
                )
                .width,
            width == 320 ? 280 : 290,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'width $width, text $textScale x',
          );
        }
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('Home showcase wires favorite, share and open actions', (
    tester,
  ) async {
    var favorites = 0;
    var shares = 0;
    var opens = 0;
    const business = Business(
      'Mercado Macacu',
      'Comércio',
      'Mercados',
      '',
      'Centro',
      0,
    );
    await tester.binding.setSurfaceSize(const Size(320, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 320,
            child: BusinessCard(
              business: business,
              saved: false,
              onFavorite: () => favorites++,
              onShare: () async => shares++,
              onOpen: () => opens++,
              onViewBusiness: () {},
              onWhatsApp: () {},
              compact: true,
              featuredShowcase: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Favoritar Mercado Macacu'));
    await tester.pump();
    await tester.tap(find.byTooltip('Compartilhar Mercado Macacu'));
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('featured-business-showcase-card')),
      ),
    );
    await tester.pump();

    expect(favorites, 1);
    expect(shares, 1);
    expect(opens, 1);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Home showcase omits ambiguous status and keeps image fallback', (
    tester,
  ) async {
    const business = Business(
      'Comércio sem imagem',
      'Comércio',
      '',
      '',
      'Centro',
      0,
      open: false,
      statusSpecified: true,
      hours: 'funciona dependendo do movimento',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 320,
            child: BusinessCard(
              business: business,
              saved: false,
              onFavorite: () {},
              onOpen: () {},
              onViewBusiness: () {},
              onWhatsApp: () {},
              compact: true,
              featuredShowcase: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('ABERTO AGORA'), findsNothing);
    expect(find.text('FECHADO AGORA'), findsNothing);
    expect(find.text('Status informado: fechado'), findsNothing);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(find.text('DESTAQUE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home showcase shows schedule-derived open and closed states', (
    tester,
  ) async {
    final time = DateTime.utc(2026, 11, 3, 18);
    final open = Business(
      'Aberto',
      'Comércio',
      '',
      '',
      'Centro',
      0,
      hours: 'Ter: 09:00 às 18:00',
      listingTier: ListingTier.premium,
      premiumUntil: DateTime.utc(2099),
    );
    final closed = Business(
      'Fechado',
      'Comércio',
      '',
      '',
      'Centro',
      0,
      hours: 'Ter: Fechado',
      listingTier: ListingTier.premium,
      premiumUntil: DateTime.utc(2099),
    );

    Future<void> show(Business business) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 320,
            child: BusinessCard(
              business: business,
              saved: false,
              onFavorite: () {},
              onOpen: () {},
              onViewBusiness: () {},
              onWhatsApp: () {},
              compact: true,
              featuredShowcase: true,
              openingStatusClock: () => time,
            ),
          ),
        ),
      ),
    );

    await show(open);
    await tester.pump();
    expect(find.text('ABERTO AGORA'), findsOneWidget);
    await show(closed);
    await tester.pump();
    expect(find.text('FECHADO AGORA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('business cards show next opening or closing responsively', (
    tester,
  ) async {
    final business = Business(
      'Mercado Macacu',
      'Comércio',
      'Mercados',
      'Mercado local.',
      'Centro',
      0,
      hours: 'Seg: 09:00 às 18:00; Ter: 08:00 às 12:00',
      listingTier: ListingTier.premium,
      premiumUntil: DateTime.utc(2099),
    );
    final now = DateTime.utc(2026, 11, 2, 15);

    for (final width in <double>[320, 360, 412]) {
      for (final featured in <bool>[false, true]) {
        await tester.binding.setSurfaceSize(Size(width, 850));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: BusinessCard(
                  business: business,
                  saved: false,
                  onFavorite: () {},
                  onOpen: () {},
                  onViewBusiness: () {},
                  onWhatsApp: () {},
                  compact: featured,
                  featuredShowcase: featured,
                  openingStatusClock: () => now,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Fecha hoje às 18h'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width featured=$featured',
        );
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
