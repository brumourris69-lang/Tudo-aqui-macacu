import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';

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
  }) =>
      MaterialApp(
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

  testWidgets('ação de edição aparece somente quando autorizada', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      wrap(saved: false, onFavorite: () {}, canEdit: true, onEdit: () => edits++),
    );
    expect(find.byTooltip('Editar estabelecimento'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar estabelecimento'));
    expect(edits, 1);
  });

  testWidgets('galeria de fotos informa imagem e total para leitor de tela', (
    tester,
  ) async {
    const withGallery = Business(
      'Estúdio Raiz', 'Beleza', 'Salão', '', 'Centro', 12,
      galleryUrls: ['https://example.com/one.jpg', 'https://example.com/two.jpg'],
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
    expect(find.bySemanticsLabel('Galeria de Estúdio Raiz, imagem 1 de 2'), findsOneWidget);
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
}
