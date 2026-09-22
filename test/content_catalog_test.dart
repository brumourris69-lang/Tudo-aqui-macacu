import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  test('o catálogo cobre os serviços essenciais da cidade', () {
    final categories = catalog.map((item) => item.name).toSet();

    expect(
      categories,
      containsAll(<String>[
        'Comércio',
        'Onde comer?',
        'Serviços',
        'Turismo',
        'Saúde',
        'Serviços úteis',
      ]),
    );
    expect(businesses, isNotEmpty);
    expect(featured, isNotEmpty);
  });

  test('empresa usa id estavel para favoritos quando disponivel', () {
    const business = Business(
      'Nome antigo',
      'Comércio',
      'Loja',
      'Descrição',
      'Centro',
      0,
      id: 'doc-estavel-123',
    );

    expect(business.favoriteKey, 'doc-estavel-123');
  });

  test('sistema de icones possui 30 identificadores unicos', () {
    expect(AppIcon.all, hasLength(30));
    expect(AppIcon.all.map((icon) => icon.key).toSet(), hasLength(30));
    expect(AppIcon.all.map((icon) => icon.assetName).toSet(), hasLength(30));
  });

  test('sistema de icones resolve arquivos oficiais esperados', () {
    expect(AppIcon.comercio.assetPath, 'assets/images/icons/01_comercio.png');
    expect(
      AppIcon.pontosTuristicos.assetPath,
      'assets/images/icons/27_pontos_turisticos.png',
    );
    expect(AppIcon.roteiros.assetPath, 'assets/images/icons/30_roteiros.png');
  });

  test('sistema de icones preserva compatibilidade com artwork antigo', () {
    expect(AppIcon.fromLegacyIndex(0), AppIcon.comercio);
    expect(AppIcon.fromLegacyIndex(5), AppIcon.turismo);
    expect(AppIcon.fromLegacyIndex(16), AppIcon.cupons);
    expect(AppIcon.fromLegacyIndex(999), AppIcon.servicos);
  });

  test('sistema de icones mapeia categoria e utilidade semanticamente', () {
    expect(AppIcon.fromCategory('Onde comer?'), AppIcon.ondeComer);
    expect(AppIcon.fromCategory('Beleza'), AppIcon.beleza);
    expect(AppIcon.fromUtilityKey('onibus'), AppIcon.onibus);
    expect(AppIcon.fromUtilityKey('coleta_lixo'), AppIcon.coletaLixo);
    expect(AppIcon.fromUtilityKey('prefeitura'), AppIcon.prefeitura);
  });

  test('url do Cloudinary recebe transformação otimizada', () {
    final optimized = cloudinaryOptimizedImageUrl(
      'https://res.cloudinary.com/demo/image/upload/v1/foto.jpg',
    );

    expect(
      optimized,
      'https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/v1/foto.jpg',
    );
  });

  test('url do Cloudinary com transformacao nao e quebrada por virgulas', () {
    final optimized = cloudinaryOptimizedImageUrl(
      ' https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/v1/foto.jpg?x=1 ',
    );

    expect(
      optimized,
      'https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/v1/foto.jpg?x=1',
    );
  });

  test('campo de imagens aceita varios links uma URL por linha', () {
    final urls = imageUrlsFromInput('''
      https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/v1/capa.jpg

      https://res.cloudinary.com/demo/image/upload/v1/foto.jpg
      ''').map(cloudinaryOptimizedImageUrl).toList();

    expect(urls, hasLength(2));
    expect(urls.first, contains('f_auto,q_auto,w_1600,c_limit'));
    expect(urls.last, contains('/f_auto,q_auto,w_1600,c_limit/v1/foto.jpg'));
  });

  test('campo de imagens ignora URL invalida e duplicada', () {
    final urls = orderedUniqueImageUrls(
      imageUrlsFromInput('''
        texto sem url
         https://res.cloudinary.com/demo/image/upload/v1/foto.jpg
        https://res.cloudinary.com/demo/image/upload/v1/foto.jpg
        '''),
    );

    expect(urls, hasLength(1));
    expect(urls.single, contains('/f_auto,q_auto,w_1600,c_limit/v1/foto.jpg'));
  });

  test('galeria preserva capa, troca capa, remove e reorganiza fotos', () {
    final gallery = orderedUniqueImageUrls([
      'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
      'https://res.cloudinary.com/demo/image/upload/v1/foto-1.jpg',
      'https://res.cloudinary.com/demo/image/upload/v1/foto-2.jpg',
    ]);

    expect(gallery.first, contains('capa.jpg'));

    final coverChanged = setCoverImageUrl(gallery, 2);
    expect(coverChanged.first, contains('foto-2.jpg'));

    final removedCover = removeImageUrl(coverChanged, 0);
    expect(removedCover.first, contains('capa.jpg'));

    final moved = moveImageUrl(removedCover, 1, -1);
    expect(moved.first, contains('foto-1.jpg'));
  });

  test('logo do estabelecimento fica separada da capa e galeria', () {
    const business = Business(
      'Estúdio',
      'Serviços',
      'Salão',
      'Descrição',
      'Centro',
      0,
      logoUrl: 'https://res.cloudinary.com/demo/image/upload/v1/logo.jpg',
      imageUrl: 'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
      galleryUrls: ['https://res.cloudinary.com/demo/image/upload/v1/foto.jpg'],
    );

    expect(business.logoUrl, contains('logo.jpg'));
    expect(business.imageUrl, contains('capa.jpg'));
    expect(business.galleryUrls.single, contains('foto.jpg'));
  });

  test('conteúdo local combina capa e galeria sem duplicar imagem', () {
    final images = contentImageUrls({
      'imageUrl': 'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
      'galleryUrls': [
        'https://res.cloudinary.com/demo/image/upload/v1/foto-1.jpg',
        'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
      ],
    });

    expect(images, hasLength(2));
    expect(images.first, contains('capa.jpg'));
    expect(images.every((url) => url.contains('f_auto,q_auto')), isTrue);
  });

  test('conteúdo local monta linha de data local e contato', () {
    final meta = localContentMeta({
      'eventDate': '25/09/2026 às 19h',
      'location': 'Centro',
      'contact': 'Secretaria de Turismo',
    });

    expect(meta, '25/09/2026 às 19h · Centro · Secretaria de Turismo');
  });

  test('utilidades usam iconKey semântico', () {
    expect(utilityIconMap.keys, containsAll(['coupons', 'alerts', 'map']));
    expect(
      utilityIconMap.keys.any((key) => RegExp(r'^icon\d+$').hasMatch(key)),
      isFalse,
    );
    expect(fallbackUtilities.every((item) => item.active), isTrue);
  });

  test(
    'métricas comerciais expõem ações esperadas sem depender de usuário',
    () {
      expect(
        metricActions,
        containsAll([
          'business_open',
          'business_whatsapp',
          'business_phone',
          'business_map',
          'business_instagram',
          'business_share',
          'coupon_open',
          'banner_view',
        ]),
      );
    },
  );
}
