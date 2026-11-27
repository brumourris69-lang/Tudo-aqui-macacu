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
    this.photoCredits = const [],
    this.subcategory = '',
    this.iconKey = '',
    this.order = 0,
  });

  factory TouristSpot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TouristSpot.fromData(doc.id, doc.data() ?? const <String, dynamic>{});

  factory TouristSpot.fromData(String id, Map<String, dynamic> data) {
    final savedImages = _touristSpotImageUrls(data);
    final curatedPhotos = savedImages.isEmpty
        ? _curatedTourismPhotos[_normalizeTouristTitle(
            (data['title'] ?? data['name'] ?? '').toString(),
          )]
        : null;
    final images = savedImages.isNotEmpty
        ? savedImages
        : curatedPhotos?.map((photo) => photo.url).toList(growable: false) ??
              const <String>[];
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
      photoCredits: curatedPhotos ?? const <TouristSpotPhotoCredit>[],
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
  final List<TouristSpotPhotoCredit> photoCredits;

  /// Existing map URL wins; otherwise search the saved location, or the spot
  /// title within Cachoeiras de Macacu. The title fallback is a Maps search,
  /// not a verified pin, and creates no coordinates or route metadata.
  String get mapDestination {
    final savedMap = _safeMapsDestination(maps);
    if (savedMap.isNotEmpty) return savedMap;

    final searchText = location.trim().isNotEmpty
        ? location.trim()
        : _municipalSearchQuery(title);
    if (searchText.isEmpty) return '';

    final search = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': searchText,
    }).toString();
    return _safeMapsDestination(search);
  }
}

class TouristSpotPhotoCredit {
  const TouristSpotPhotoCredit({
    required this.url,
    required this.author,
    required this.license,
    required this.sourceUrl,
    required this.licenseUrl,
  });

  final String url;
  final String author;
  final String license;
  final String sourceUrl;
  final String licenseUrl;
}

final Map<String, List<TouristSpotPhotoCredit>> _curatedTourismPhotos = {
  'cachoeira do tenebroso': [
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/49/Tenebroso.JPG/1280px-Tenebroso.JPG',
      author: 'Lpersil',
      license: 'CC BY-SA 4.0',
      sourceUrl: 'https://commons.wikimedia.org/wiki/File:Tenebroso.JPG',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    ),
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/45/Cachoeira_Tenebroso_-_panoramio.jpg/1280px-Cachoeira_Tenebroso_-_panoramio.jpg',
      author: 'TMbux',
      license: 'CC BY-SA 3.0',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Cachoeira_Tenebroso_-_panoramio.jpg',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/3.0/',
    ),
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/87/Cachoeira_do_Tenebroso.jpg/1280px-Cachoeira_do_Tenebroso.jpg',
      author: 'VagnerMello',
      license: 'CC BY-SA 4.0',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Cachoeira_do_Tenebroso.jpg',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    ),
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/26/Topo_da_Cachoeira_do_Tenebroso.jpg/1280px-Topo_da_Cachoeira_do_Tenebroso.jpg',
      author: 'VagnerMello',
      license: 'CC BY-SA 4.0',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Topo_da_Cachoeira_do_Tenebroso.jpg',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    ),
  ],
  'poço do valério': [
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/13/APA_da_Bacia_do_Rio_Macacu_Giovani_Sardinha_%281%29.jpg/1280px-APA_da_Bacia_do_Rio_Macacu_Giovani_Sardinha_%281%29.jpg',
      author: 'Giojva',
      license: 'CC BY-SA 4.0',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:APA_da_Bacia_do_Rio_Macacu_Giovani_Sardinha_(1).jpg',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    ),
  ],
  'pedra do faraó': [
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/75/Pedra_do_fara%C3%B3.jpg/1280px-Pedra_do_fara%C3%B3.jpg',
      author: 'Evertonsilvadarosa fotografo',
      license: 'CC BY-SA 4.0',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Pedra_do_fara%C3%B3.jpg',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    ),
  ],
  'mirante da serra': [
    const TouristSpotPhotoCredit(
      url:
          'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/96/Mirante_da_serra_Cachoeiras_de_Macacu.jpg/1280px-Mirante_da_serra_Cachoeiras_de_Macacu.jpg',
      author: 'Vitorperrut555',
      license: 'CC BY-SA 4.0',
      sourceUrl:
          'https://commons.wikimedia.org/wiki/File:Mirante_da_serra_Cachoeiras_de_Macacu.jpg',
      licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    ),
  ],
};

String _normalizeTouristTitle(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _municipalSearchQuery(String title) {
  final name = title.trim();
  if (name.isEmpty || name == 'Local turístico') return '';
  return '$name, Cachoeiras de Macacu, RJ, Brasil';
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
  ).take(5).toList(growable: false);
}

String _safeMapsDestination(String value) {
  final target = value.trim();
  if (target.isEmpty) return '';
  final uri = Uri.tryParse(target);
  if (uri == null || !isAllowedExternalUri(uri)) return '';
  if (!const {'https', 'geo'}.contains(uri.scheme.toLowerCase())) return '';
  return target;
}
