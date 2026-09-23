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
    expect(business.open, isFalse);
    expect(business.whatsappUrl, 'https://wa.me/21999999999');
    expect(business.phoneUrl, 'tel:2133333333');
    expect(business.instagramUrl, 'https://instagram.com/studioraiz');
    expect(business.maps, 'https://maps.google.com/studio');
    expect(business.logoUrl, contains('/f_auto,q_auto,w_1600,c_limit/'));
    expect(business.imageUrl, contains('/f_auto,q_auto,w_1600,c_limit/'));
    expect(business.galleryUrls, hasLength(2));
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
    expect(business.open, isTrue);
    expect(business.maps, 'https://maps.google.com/legado');
    expect(business.logoUrl, '');
    expect(business.imageUrl, '');
    expect(business.galleryUrls, isEmpty);
    expect(business.services, isEmpty);
    expect(business.products, isEmpty);
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
}
