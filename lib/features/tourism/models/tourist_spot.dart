import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/media/media_url_service.dart';

class TouristSpot {
  const TouristSpot({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.location,
    required this.maps,
    required this.images,
    required this.additionalInfo,
  });

  factory TouristSpot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TouristSpot.fromData(doc.id, doc.data() ?? const <String, dynamic>{});

  factory TouristSpot.fromData(String id, Map<String, dynamic> data) {
    final images = _touristSpotImageUrls(data);
    return TouristSpot(
      id: id,
      title: (data['title'] ?? data['name'] ?? 'Local turístico').toString(),
      category: (data['category'] ?? data['type'] ?? 'cachoeiras')
          .toString()
          .toLowerCase(),
      description: (data['description'] ?? '').toString(),
      location: (data['location'] ?? data['address'] ?? '').toString(),
      maps: (data['maps'] ?? data['mapsUrl'] ?? data['link'] ?? '').toString(),
      images: images,
      additionalInfo: (data['additionalInfo'] ?? '').toString(),
    );
  }

  final String id, title, category, description, location, maps, additionalInfo;
  final List<String> images;
}

List<String> _touristSpotImageUrls(Map<String, dynamic> data) {
  final gallery = ((data['galleryUrls'] as List?) ?? const [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .map(cloudinaryOptimizedImageUrl)
      .toList();
  final cover = cloudinaryOptimizedImageUrl(
    (data['imageUrl'] ?? '').toString(),
  );
  if (cover.isNotEmpty) {
    gallery.remove(cover);
    gallery.insert(0, cover);
  }
  return gallery;
}
