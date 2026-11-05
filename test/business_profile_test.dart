import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_action_button.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_card.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_hero_media.dart';

void main() {
  const business = Business(
    'Estúdio Raiz',
    'Beleza',
    'Cabeleireiros e salões',
    'Cuidado, beleza e autoestima para você.',
    'Centro · Cachoeiras de Macacu',
    12,
    phone: '(21) 99999-0000',
    whatsapp: '(21) 98888-0000',
    instagram: '@estudioraiz',
    maps: 'https://maps.google.com/?q=Estudio+Raiz',
    open: true,
  );

  Widget wrap({
    required bool saved,
    required VoidCallback onFavorite,
    bool canEdit = false,
    VoidCallback? onEdit,
  }) => MaterialApp(
    home: BusinessProfile(
      business: business,
      saved: saved,
      onFavorite: onFavorite,
      canEdit: canEdit,
      onEdit: onEdit,
    ),
  );

  testWidgets('BusinessProfile renderiza dados principais da empresa', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(saved: false, onFavorite: () {}));

    expect(find.text('Estúdio Raiz'), findsOneWidget);
    expect(find.text('Beleza · Cabeleireiros e salões'), findsOneWidget);
    expect(
      find.text('Cuidado, beleza e autoestima para você.'),
      findsOneWidget,
    );
    expect(find.text('Centro · Cachoeiras de Macacu'), findsOneWidget);
    expect(find.text('Status informado: aberto'), findsOneWidget);
    expect(find.text('ABERTO AGORA'), findsNothing);
  });

  testWidgets('BusinessProfile mostra o próximo horário seguro', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const withHours = Business(
      'Mercado Macacu',
      'Comércio',
      'Mercados',
      'Atendimento local.',
      'Centro',
      0,
      hours: 'Seg: 09:00 às 18:00; Ter: 08:00 às 12:00',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: withHours,
          saved: false,
          onFavorite: () {},
          openingStatusClock: () => DateTime.utc(2026, 11, 2, 15),
        ),
      ),
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('business-hours-info')),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aberto agora'), findsOneWidget);
    expect(find.text('Fecha hoje às 18h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'perfil usa capa premium com logo sobreposta e contador da galeria',
    (tester) async {
      const withVisualMedia = Business(
        'Estúdio Raiz',
        'Beleza',
        'Cabeleireiros e salões',
        'Cuidado, beleza e autoestima para você.',
        'Centro · Cachoeiras de Macacu',
        12,
        logoUrl: 'https://example.invalid/logo.png',
        galleryUrls: [
          'https://example.invalid/capa.png',
          'https://example.invalid/interior.png',
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BusinessProfile(
            business: withVisualMedia,
            saved: false,
            onFavorite: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('business-profile-hero')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-profile-logo-overlap')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-profile-gallery-count')),
        findsOneWidget,
      );
      expect(find.text('2 fotos'), findsOneWidget);
      expect(
        tester
            .widget<BusinessHeroMedia>(find.byType(BusinessHeroMedia))
            .useLogoFallback,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('moldura sobreposta do logo também tem formato circular', (
    tester,
  ) async {
    const withLogo = Business(
      'Estúdio Raiz',
      'Beleza',
      'Cabeleireiros e salões',
      'Cuidado, beleza e autoestima para você.',
      'Centro · Cachoeiras de Macacu',
      12,
      logoUrl: 'https://example.invalid/logo.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: withLogo,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );

    final frame = tester.widget<Container>(
      find.byKey(const ValueKey('business-profile-logo-overlap')),
    );
    final decoration = frame.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(frame.clipBehavior, Clip.antiAlias);
    expect(find.byType(ClipOval), findsOneWidget);
  });

  testWidgets('perfil permite passar lateralmente pelas fotos da capa', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const withGallery = Business(
      'Estúdio Raiz',
      'Beleza',
      'Cabeleireiros e salões',
      'Cuidado, beleza e autoestima para você.',
      'Centro · Cachoeiras de Macacu',
      12,
      galleryUrls: [
        'https://example.invalid/capa.png',
        'https://example.invalid/interior.png',
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: withGallery,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Galeria de Estúdio Raiz, imagem 1 de 2'),
      findsOneWidget,
    );

    final pageView = find.byType(PageView);
    final pageWidth = tester.getSize(pageView).width;
    await tester.drag(pageView, Offset(-pageWidth * .75, 0));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Galeria de Estúdio Raiz, imagem 2 de 2'),
      findsOneWidget,
    );
  });

  testWidgets('perfil acomoda endereço e descrição longos em telas compactas', (
    tester,
  ) async {
    const longDescription =
        'Um espaço acolhedor com atendimento personalizado, produtos locais '
        'e informações completas para ajudar cada pessoa a planejar sua visita '
        'com tranquilidade e conhecer os serviços disponíveis.';
    const longBusiness = Business(
      'Empório Artesanal da Serra de Macacu',
      'Comércio',
      'Produtos locais e presentes',
      longDescription,
      'Estrada do Vale Verde, próximo à praça principal, Cachoeiras de Macacu, RJ',
      12,
      statusSpecified: false,
    );

    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 820));
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessProfile(
            business: longBusiness,
            saved: false,
            onFavorite: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(longDescription), findsOneWidget);
      expect(
        find.byKey(const ValueKey('business-profile-location')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });

  testWidgets('BusinessProfile omits separator when subcategory is empty', (
    tester,
  ) async {
    const withoutSubcategory = Business(
      'Loja sem subcategoria',
      'Comércio',
      '',
      '',
      'Centro',
      0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: withoutSubcategory,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );

    expect(find.text('Comércio'), findsOneWidget);
    expect(find.text('Comércio ·'), findsNothing);
  });

  testWidgets('BusinessProfile preserva botão de favorito e callback', (
    tester,
  ) async {
    var favoriteCount = 0;

    await tester.pumpWidget(
      wrap(saved: false, onFavorite: () => favoriteCount++),
    );
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    expect(favoriteCount, 1);

    await tester.pumpWidget(
      wrap(saved: true, onFavorite: () => favoriteCount++),
    );
    await tester.tap(find.byIcon(Icons.favorite_rounded));
    expect(favoriteCount, 2);
  });

  testWidgets('favorito tem rótulo acessível e edição fica oculta por padrão', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(saved: false, onFavorite: () {}));

    expect(find.byTooltip('Favoritar Estúdio Raiz'), findsOneWidget);
    expect(find.text('Editar estabelecimento'), findsNothing);
  });

  testWidgets('rascunho de prévia não oferece compartilhamento público', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: business,
          saved: false,
          onFavorite: () {},
          previewMode: true,
        ),
      ),
    );
    expect(find.byTooltip('Compartilhar'), findsNothing);
  });

  testWidgets('ação de edição aparece somente quando autorizada', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      wrap(
        saved: false,
        onFavorite: () {},
        canEdit: true,
        onEdit: () => edits++,
      ),
    );
    expect(find.byTooltip('Editar estabelecimento'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar estabelecimento'));
    expect(edits, 1);
  });

  testWidgets('galeria de fotos informa imagem e total para leitor de tela', (
    tester,
  ) async {
    const withGallery = Business(
      'Estúdio Raiz',
      'Beleza',
      'Salão',
      '',
      'Centro',
      12,
      galleryUrls: [
        'https://example.com/one.jpg',
        'https://example.com/two.jpg',
      ],
      videoUrls: ['https://youtu.be/abc123'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: withGallery,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Galeria de Estúdio Raiz, imagem 1 de 2'),
      findsOneWidget,
    );
    expect(find.text('Assistir vídeo'), findsOneWidget);
    expect(find.text('Vídeo 1'), findsOneWidget);
  });

  testWidgets('card público de estabelecimento usa a capa da galeria', (
    tester,
  ) async {
    final business = Business.fromData('loja-com-galeria', {
      'name': 'Loja com galeria',
      'imageUrl': 'https://example.com/cover.jpg',
      'galleryUrls': [
        'https://example.com/other.jpg',
        'https://example.com/cover.jpg',
      ],
    });
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

    final cover = tester.widget<Image>(
      find.byKey(const ValueKey('business-card-cover-Loja com galeria')),
    );
    expect((cover.image as NetworkImage).url, 'https://example.com/cover.jpg');
    expect(find.bySemanticsLabel('Capa de Loja com galeria'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('galeria pública sem fotos mantém um fundo seguro', (
    tester,
  ) async {
    const business = Business('Loja sem fotos', 'Comércio', '', '', '', 0);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 320,
          width: 360,
          child: BusinessHeroMedia(business: business),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BusinessProfile exibe CTAs externos quando há dados', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(saved: false, onFavorite: () {}));

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Ligar'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('Como chegar'), findsOneWidget);
  });

  testWidgets('BusinessProfile dá cor de marca a cada ação de contato', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(saved: false, onFavorite: () {}));

    List<Color> gradient(String key) => tester
        .widget<BusinessActionButton>(find.byKey(ValueKey(key)))
        .gradientColors;

    expect(gradient('business-action-whatsapp').first, const Color(0xFF32D66E));
    expect(gradient('business-action-phone').last, const Color(0xFF087C3A));
    expect(gradient('business-action-instagram'), hasLength(3));
    expect(gradient('business-action-maps').first, const Color(0xFF1488F5));
  });

  testWidgets('ações premium ficam em grade de duas colunas e mantêm vídeos', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const businessWithActions = Business(
      'Comércio completo',
      'Serviços',
      'Assistência',
      'Descrição do estabelecimento.',
      'Centro',
      0,
      phone: '(21) 99999-0000',
      whatsapp: '(21) 98888-0000',
      instagram: '@comercio',
      maps: 'https://maps.google.com/?q=centro',
      videoUrls: ['https://youtu.be/video1', 'https://vimeo.com/12345'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: businessWithActions,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('business-actions-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .mainAxisExtent,
      64,
    );
    expect(find.byKey(const ValueKey('business-action-phone')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('business-action-whatsapp')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('business-action-video-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ações premium exibem títulos completos em larguras móveis', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const businessWithActions = Business(
      'Comércio compacto',
      'Serviços',
      '',
      '',
      'Centro',
      0,
      phone: '(21) 99999-0000',
      instagram: '@comercio',
      maps: 'https://maps.google.com/?q=centro',
      videoUrls: ['https://youtu.be/video1'],
    );

    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessProfile(
            business: businessWithActions,
            saved: false,
            onFavorite: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('business-actions-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        2,
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .mainAxisExtent,
        64,
      );
      for (final label in [
        'Ligar',
        'Instagram',
        'Como chegar',
        'Assistir vídeo',
      ]) {
        final titleFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.replaceAll('\n', ' ') == label,
        );
        final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
        final textWidget = tester.widget<Text>(titleFinder);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$label @ $width');
        expect(textWidget.data!.replaceAll('\n', ' '), label);
        expect(textWidget.maxLines, 2, reason: '$label @ $width');
        expect(
          textWidget.overflow,
          TextOverflow.clip,
          reason: '$label @ $width',
        );
      }
      expect(tester.takeException(), isNull, reason: 'largura $width');
    }
  });

  testWidgets('ações premium usam uma coluna com texto ampliado', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const accessibleBusiness = Business(
      'Comércio acessível',
      'Serviços',
      '',
      '',
      'Centro',
      0,
      phone: '(21) 99999-0000',
      instagram: '@comercio',
      maps: 'https://maps.google.com/?q=centro',
      videoUrls: ['https://youtu.be/video1'],
      statusSpecified: false,
    );

    for (final scale in [1.5, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: BusinessProfile(
              business: accessibleBusiness,
              saved: false,
              onFavorite: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('business-actions-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        1,
      );
      for (final label in [
        'Ligar',
        'Instagram',
        'Como chegar',
        'Assistir vídeo',
      ]) {
        final titleFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.replaceAll('\n', ' ') == label,
        );
        final title = tester.widget<Text>(titleFinder);
        final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
        expect(title.data!.replaceAll('\n', ' '), label);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$label @ $scale');
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('grade compacta aumenta com texto acessível sem overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const accessibleBusiness = Business(
      'Comércio acessível',
      'Serviços',
      '',
      '',
      'Centro',
      0,
      phone: '(21) 99999-0000',
      instagram: '@comercio',
      maps: 'https://maps.google.com/?q=centro',
      videoUrls: ['https://youtu.be/video1'],
      statusSpecified: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.5),
          ),
          child: BusinessProfile(
            business: accessibleBusiness,
            saved: false,
            onFavorite: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('business-actions-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .mainAxisExtent,
      greaterThan(64),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ações de vídeo usam cores de YouTube e Vimeo', (tester) async {
    const businessWithVideos = Business(
      'Estúdio Raiz',
      'Beleza',
      'Salão',
      '',
      'Centro',
      12,
      videoUrls: ['https://youtu.be/abc123', 'https://vimeo.com/123456'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: businessWithVideos,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );

    List<Color> gradient(int index) => tester
        .widget<BusinessActionButton>(
          find.byKey(ValueKey('business-action-video-$index')),
        )
        .gradientColors;

    expect(gradient(0).first, const Color(0xFFFF3D36));
    expect(gradient(1).first, const Color(0xFF36A9E8));
  });

  testWidgets('BusinessProfile oculta ações com links inválidos', (
    tester,
  ) async {
    const invalidContacts = Business(
      'Contato inválido',
      'Comércio',
      '',
      '',
      '',
      0,
      phone: '1234567',
      whatsapp: 'https://example.com/contact',
      instagram: 'https://evil.example/profile',
      maps: 'javascript:alert(1)',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessProfile(
          business: invalidContacts,
          saved: false,
          onFavorite: () {},
        ),
      ),
    );

    expect(find.text('WhatsApp'), findsNothing);
    expect(find.text('Ligar'), findsNothing);
    expect(find.text('Instagram'), findsNothing);
    expect(find.text('Como chegar'), findsNothing);
  });
}
