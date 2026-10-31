import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';
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
    expect(find.text('Assistir vídeo 1'), findsOneWidget);
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
