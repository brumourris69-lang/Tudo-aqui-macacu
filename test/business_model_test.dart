import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';

void main() {
  test('Business.fromData preserva documento completo', () {
    final business = Business.fromData('studio-raiz', {
      'name': 'Estúdio Raiz',
      'category': 'Beleza',
      'subcategory': 'Cabeleireiros',
      'shortDescription': 'Cuidado e autoestima',
      'location': 'Centro',
      'artwork': 21,
      'featured': true,
      'iconKey': 'cachoeiras',
      'open': false,
      'whatsapp': '21999999999',
      'phone': '2133333333',
      'instagram': '@studioraiz',
      'maps': 'https://maps.google.com/studio',
      'logoUrl': 'https://res.cloudinary.com/demo/image/upload/v1/logo.jpg',
      'imageUrl': 'https://res.cloudinary.com/demo/image/upload/v1/capa.jpg',
      'galleryUrls': [
        'https://res.cloudinary.com/demo/image/upload/v1/foto1.jpg',
        '',
        'https://res.cloudinary.com/demo/image/upload/v1/foto2.jpg',
      ],
      'videoUrls': ['https://youtu.be/abc123', '', 'https://vimeo.com/123456'],
      'hours': 'Seg a sex',
      'services': ['Corte', '', 'Escova'],
      'products': ['Shampoo'],
      'additionalInfo': 'Atende com hora marcada',
      'promotionTitle': 'Promoção',
      'promotionDescription': '10% off',
    });

    expect(business.id, 'studio-raiz');
    expect(business.favoriteKey, 'studio-raiz');
    expect(business.name, 'Estúdio Raiz');
    expect(business.category, 'Beleza');
    expect(business.subcategory, 'Cabeleireiros');
    expect(business.description, 'Cuidado e autoestima');
    expect(business.location, 'Centro');
    expect(business.artwork, 21);
    expect(business.featured, isTrue);
    expect(business.iconKey, 'cachoeiras');
    expect(business.open, isFalse);
    expect(business.whatsappUrl, 'https://wa.me/21999999999');
    expect(business.phoneUrl, 'tel:2133333333');
    expect(business.instagramUrl, 'https://instagram.com/studioraiz');
    expect(business.maps, 'https://maps.google.com/studio');
    expect(business.logoUrl, contains('/f_auto,q_auto,w_1600,c_limit/'));
    expect(business.imageUrl, contains('/f_auto,q_auto,w_1600,c_limit/'));
    expect(business.galleryUrls, hasLength(3));
    expect(business.galleryUrls.first, business.imageUrl);
    expect(
      business.galleryUrls,
      containsAll([contains('foto1.jpg'), contains('foto2.jpg')]),
    );
    expect(business.videoUrls, [
      'https://youtu.be/abc123',
      'https://vimeo.com/123456',
    ]);
    expect(business.services, ['Corte', 'Escova']);
    expect(business.products, ['Shampoo']);
    expect(business.hours, 'Seg a sex');
    expect(business.additionalInfo, 'Atende com hora marcada');
    expect(business.promotionTitle, 'Promoção');
    expect(business.promotionDescription, '10% off');
  });

  test('Business.fromData usa fallbacks quando campos opcionais faltam', () {
    final business = Business.fromData('doc-fallback', {
      'title': 'Nome legado',
      'description': 'Descrição legada',
      'address': 'Endereço legado',
      'mapsUrl': 'https://maps.google.com/legado',
    });

    expect(business.id, 'doc-fallback');
    expect(business.name, 'Nome legado');
    expect(business.category, 'Comércio');
    expect(business.subcategory, '');
    expect(business.description, 'Descrição legada');
    expect(business.location, 'Endereço legado');
    expect(business.artwork, 0);
    expect(business.featured, isFalse);
    expect(business.iconKey, isEmpty);
    expect(business.open, isTrue);
    expect(business.maps, 'https://maps.google.com/legado');
    expect(business.logoUrl, '');
    expect(business.imageUrl, '');
    expect(business.galleryUrls, isEmpty);
    expect(business.videoUrls, isEmpty);
    expect(business.services, isEmpty);
    expect(business.products, isEmpty);
  });

  test('capa pública também define o primeiro item da galeria', () {
    final cover = 'https://example.com/cover.jpg';
    final firstPhoto = 'https://example.com/first.jpg';
    final business = Business.fromData('capa-fora-de-ordem', {
      'imageUrl': cover,
      'galleryUrls': [firstPhoto, cover, firstPhoto, ''],
    });

    expect(business.imageUrl, cover);
    expect(business.galleryUrls, [cover, firstPhoto]);
  });

  test('Business.favoriteKey usa nome quando não há id', () {
    const business = Business(
      'Nome local',
      'Comércio',
      'Loja',
      'Descrição',
      'Centro',
      0,
    );

    expect(business.favoriteKey, 'Nome local');
  });

  test('ações públicas rejeitam contatos malformados', () {
    const business = Business(
      'Contato inválido',
      'Comércio',
      '',
      '',
      '',
      0,
      phone: 'tel:javascript:alert(1)',
      whatsapp: 'https://example.com/not-whatsapp',
      instagram: 'https://evil.example/@loja',
    );
    expect(business.phoneUrl, isEmpty);
    expect(business.whatsappUrl, isEmpty);
    expect(business.instagramUrl, isEmpty);
    expect(business.mapsActionUrl, isEmpty);
    expect(
      const Business(
        'Curto',
        'Comércio',
        '',
        '',
        '',
        0,
        phone: '1234567',
      ).phoneUrl,
      isEmpty,
    );
  });
}
