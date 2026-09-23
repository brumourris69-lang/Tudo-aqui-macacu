import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/media/media_url_service.dart';

class Business {
  const Business(
    this.name,
    this.category,
    this.subcategory,
    this.description,
    this.location,
    this.artwork, {
    this.id = '',
    this.featured = false,
    this.open = true,
    this.whatsapp = '',
    this.phone = '',
    this.instagram = '',
    this.maps = '',
    this.logoUrl = '',
    this.imageUrl = '',
    this.galleryUrls = const [],
    this.hours = '',
    this.services = const [],
    this.products = const [],
    this.additionalInfo = '',
    this.promotionTitle = '',
    this.promotionDescription = '',
  });

  factory Business.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) => Business.fromData(
    document.id,
    document.data() ?? const <String, dynamic>{},
  );

  factory Business.fromData(String id, Map<String, dynamic> data) {
    return Business(
      (data['name'] ?? data['title'] ?? 'Estabelecimento').toString(),
      (data['category'] ?? 'Comércio').toString(),
      (data['subcategory'] ?? '').toString(),
      (data['shortDescription'] ?? data['description'] ?? '').toString(),
      (data['location'] ?? data['address'] ?? 'Cachoeiras de Macacu')
          .toString(),
      (data['artwork'] as num?)?.toInt() ?? 0,
      id: id,
      featured: data['featured'] == true,
      open: data['open'] != false,
      whatsapp: (data['whatsapp'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      instagram: (data['instagram'] ?? '').toString(),
      maps: (data['maps'] ?? data['mapsUrl'] ?? '').toString(),
      logoUrl: cloudinaryOptimizedImageUrl((data['logoUrl'] ?? '').toString()),
      imageUrl: cloudinaryOptimizedImageUrl(
        (data['imageUrl'] ?? '').toString(),
      ),
      galleryUrls: ((data['galleryUrls'] as List?) ?? const [])
          .map((item) => cloudinaryOptimizedImageUrl(item.toString()))
          .where((item) => item.isNotEmpty)
          .toList(),
      hours: (data['hours'] ?? '').toString(),
      services: ((data['services'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      products: ((data['products'] as List?) ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      additionalInfo: (data['additionalInfo'] ?? '').toString(),
      promotionTitle: (data['promotionTitle'] ?? '').toString(),
      promotionDescription: (data['promotionDescription'] ?? '').toString(),
    );
  }

  final String id,
      name,
      category,
      subcategory,
      description,
      location,
      whatsapp,
      phone,
      instagram,
      maps,
      logoUrl,
      imageUrl;
  final List<String> galleryUrls;
  final String hours, additionalInfo, promotionTitle, promotionDescription;
  final List<String> services, products;
  final int artwork;
  final bool featured, open;

  String get favoriteKey => id.isEmpty ? name : id;

  String get whatsappUrl {
    final value = whatsapp.trim();
    if (value.startsWith('http')) return value;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? '' : 'https://wa.me/$digits';
  }

  String get phoneUrl =>
      phone.trim().startsWith('tel:') ? phone.trim() : 'tel:${phone.trim()}';

  String get instagramUrl {
    final value = instagram.trim();
    if (value.startsWith('http')) return value;
    final handle = value.replaceFirst('@', '');
    return handle.isEmpty ? '' : 'https://instagram.com/$handle';
  }
}
