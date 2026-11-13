import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/media/media_url_service.dart';
import '../../../core/utils/external_url.dart';

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
    this.subcategory = '',
    this.iconKey = '',
    this.order = 0,
  });

  factory TouristSpot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TouristSpot.fromData(doc.id, doc.data() ?? const <String, dynamic>{});

  factory TouristSpot.fromData(String id, Map<String, dynamic> data) {
    final images = _touristSpotImageUrls(data);
    return TouristSpot(
      id: id,
      title: (data['title'] ?? data['name'] ?? 'Local turístico').toString(),
      // Missing classification stays unclassified; do not publish it under a
      // made-up public category.
      category: (data['category'] ?? data['type'] ?? '')
          .toString()
          .toLowerCase(),
      description: (data['description'] ?? '').toString(),
      location: (data['location'] ?? data['address'] ?? '').toString(),
      subcategory: (data['subcategory'] ?? '').toString(),
      iconKey: (data['iconKey'] ?? '').toString(),
      order: data['order'] is num ? (data['order'] as num).toInt() : 0,
      maps: _safeMapsDestination(
        (data['maps'] ?? data['mapsUrl'] ?? data['link'] ?? '').toString(),
      ),
      images: images,
      additionalInfo: (data['additionalInfo'] ?? '').toString(),
    );
  }

  final String id,
      title,
      category,
      description,
      location,
      subcategory,
      iconKey,
      maps,
      additionalInfo;
  final int order;
  final List<String> images;

  /// Existing map URL wins; otherwise use the saved location verbatim as a
  /// Maps search query. This creates no coordinates or route metadata.
  String get mapDestination {
    final savedMap = _safeMapsDestination(maps);
    if (savedMap.isNotEmpty) return savedMap;

    final savedLocation = location.trim();
    if (savedLocation.isEmpty) return '';

    final search = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': savedLocation,
    }).toString();
    return _safeMapsDestination(search);
  }
}

List<String> _touristSpotImageUrls(Map<String, dynamic> data) {
  final gallery = data['galleryUrls'];
  return orderedUniqueImageUrls(
    imageUrlsFromInput(
      [
        (data['imageUrl'] ?? '').toString(),
        if (gallery is List) ...gallery.whereType<String>(),
      ].join('\n'),
    ),
  ).take(3).toList(growable: false);
}

String _safeMapsDestination(String value) {
  final target = value.trim();
  if (target.isEmpty) return '';
  final uri = Uri.tryParse(target);
  if (uri == null || !isAllowedExternalUri(uri)) return '';
  if (!const {'https', 'geo'}.contains(uri.scheme.toLowerCase())) return '';
  return target;
}
