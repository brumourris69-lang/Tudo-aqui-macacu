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
    this.statusSpecified = true,
    this.whatsapp = '',
    this.phone = '',
    this.instagram = '',
    this.maps = '',
    this.logoUrl = '',
    this.imageUrl = '',
    this.galleryUrls = const [],
    this.videoUrls = const [],
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
    final storedCover = cloudinaryOptimizedImageUrl(
      (data['imageUrl'] ?? '').toString(),
    );
    final storedGallery = data['galleryUrls'] is List
        ? (data['galleryUrls'] as List).map((item) => item.toString())
        : const <String>[];
    final galleryUrls = orderedUniqueImageUrls([
      if (storedCover.isNotEmpty) storedCover,
      ...storedGallery,
    ]);
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
      statusSpecified: data['open'] is bool,
      whatsapp: (data['whatsapp'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      instagram: (data['instagram'] ?? '').toString(),
      maps: (data['maps'] ?? data['mapsUrl'] ?? '').toString(),
      logoUrl: cloudinaryOptimizedImageUrl((data['logoUrl'] ?? '').toString()),
      imageUrl: galleryUrls.isEmpty ? storedCover : galleryUrls.first,
      galleryUrls: galleryUrls,
      videoUrls: ((data['videoUrls'] as List?) ?? const [])
          .map((item) => item.toString().trim())
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
  final List<String> videoUrls;
  final String hours, additionalInfo, promotionTitle, promotionDescription;
  final List<String> services, products;
  final int artwork;
  final bool featured, open, statusSpecified;

  List<String> get displayImageUrls => orderedUniqueImageUrls([
    if (imageUrl.trim().isNotEmpty) imageUrl,
    ...galleryUrls,
  ]);

  String get favoriteKey => id.isEmpty ? name : id;

  String get categoryLabel {
    final primary = category.trim();
    final secondary = subcategory.trim();
    if (secondary.isEmpty || secondary.toLowerCase() == primary.toLowerCase()) {
      return primary;
    }
    return '$primary · $secondary';
  }

  String get whatsappUrl {
    final value = whatsapp.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      if (uri.scheme == 'https' &&
          uri.host.toLowerCase() == 'wa.me' &&
          uri.userInfo.isEmpty &&
          RegExp(r'^/\d{8,15}$').hasMatch(uri.path) &&
          uri.query.isEmpty &&
          uri.fragment.isEmpty) {
        return uri.toString();
      }
      return '';
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 && digits.length <= 15
        ? 'https://wa.me/$digits'
        : '';
  }

  String get phoneUrl {
    final value = phone.trim();
    final number = value.toLowerCase().startsWith('tel:')
        ? value.substring(4)
        : value;
    if (!RegExp(r'^\+?[\d\s().-]+$').hasMatch(number)) return '';
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) return '';
    final prefix = number.trim().startsWith('+') ? '+' : '';
    return 'tel:$prefix$digits';
  }

  String get instagramUrl {
    final value = instagram.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      final host = uri.host.toLowerCase();
      if (uri.scheme == 'https' &&
          (host == 'instagram.com' || host == 'www.instagram.com') &&
          uri.userInfo.isEmpty &&
          RegExp(r'^/[A-Za-z0-9._]{1,30}/?$').hasMatch(uri.path) &&
          uri.query.isEmpty &&
          uri.fragment.isEmpty) {
        return uri.toString();
      }
      return '';
    }
    final handle = value.startsWith('@') ? value.substring(1) : value;
    return RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(handle)
        ? 'https://instagram.com/$handle'
        : '';
  }

  String get mapsActionUrl {
    final value = maps.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || uri.userInfo.isNotEmpty) return '';
    if (uri.scheme == 'https' && uri.host.trim().isNotEmpty) return value;
    if (uri.scheme == 'geo' && uri.path.trim().isNotEmpty) return value;
    return '';
  }
}
