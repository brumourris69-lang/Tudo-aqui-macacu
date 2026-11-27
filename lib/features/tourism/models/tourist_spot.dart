import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
    final titleKey = _normalizeTouristTitle(
      (data['title'] ?? data['name'] ?? '').toString(),
    );
    final curatedPhotos = savedImages.isNotEmpty
        ? null
        : _curatedTourismPhotos[titleKey] ??
              (kDebugMode ? _developmentReferencePhotos[titleKey] : null);
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

/// Reference photos gathered from public user-contributed pages. Their
/// redistribution licenses have not been confirmed, so they are deliberately
/// available only in debug builds and never become a production fallback.
final Map<String, List<TouristSpotPhotoCredit>> _developmentReferencePhotos = {
  'cachoeira do vale perdido': [
    _developmentPhoto(
      'https://s2.wklcdn.com/image_159/4779763/190143063/117531338.700x525.jpg',
      'lipeematoos',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-vale-perdido-castalia-190143053',
    ),
    _developmentPhoto(
      'https://s1.wklcdn.com/image_159/4779763/149894266/94356571Master.jpg',
      'lipeematoos',
      'https://pt.wikiloc.com/trilhas-trekking/trilha-do-vale-perdido-149894262',
    ),
    _developmentPhoto(
      'https://s2.wklcdn.com/image_159/4779763/149894265/94356569.400x300.jpg',
      'lipeematoos',
      'https://pt.wikiloc.com/trilhas-trekking/trilha-do-vale-perdido-149894262',
    ),
  ],
  'cachoeira do salto': [
    _developmentPhoto(
      'https://s0.wklcdn.com/image_101/3040733/249854346/147393924.400x300.jpg',
      'XRVictorSilva',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-do-salto-serra-do-soarinho-papucaia-macacu-rj-249854346',
    ),
    _developmentPhoto(
      'https://s0.wklcdn.com/image_101/3040733/249854346/147393927.400x300.jpg',
      'XRVictorSilva',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-do-salto-serra-do-soarinho-papucaia-macacu-rj-249854346',
    ),
    _developmentPhoto(
      'https://s2.wklcdn.com/image_101/3040733/249854346/147393962.400x300.jpg',
      'XRVictorSilva',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-do-salto-serra-do-soarinho-papucaia-macacu-rj-249854346',
    ),
  ],
  'cachoeira do salto serra do soarinho': [
    _developmentPhoto(
      'https://s0.wklcdn.com/image_101/3040733/249854346/147393924.400x300.jpg',
      'XRVictorSilva',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-do-salto-serra-do-soarinho-papucaia-macacu-rj-249854346',
    ),
    _developmentPhoto(
      'https://s0.wklcdn.com/image_101/3040733/249854346/147393927.400x300.jpg',
      'XRVictorSilva',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-do-salto-serra-do-soarinho-papucaia-macacu-rj-249854346',
    ),
    _developmentPhoto(
      'https://s2.wklcdn.com/image_101/3040733/249854346/147393962.400x300.jpg',
      'XRVictorSilva',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-do-salto-serra-do-soarinho-papucaia-macacu-rj-249854346',
    ),
  ],
  'poço das meninas': [
    _developmentPhoto(
      'https://s2.wklcdn.com/image_413/12390720/126457240/80780078.400x300.jpg',
      'Sandra Leal 2',
      'https://pt.wikiloc.com/trilhas-trekking/poco-das-meninas-cachoeiras-de-macacu-126457240',
    ),
    _developmentPhoto(
      'https://s1.wklcdn.com/image_413/12390720/126457240/80780110.400x300.jpg',
      'Sandra Leal 2',
      'https://pt.wikiloc.com/trilhas-trekking/poco-das-meninas-cachoeiras-de-macacu-126457240',
    ),
    _developmentPhoto(
      'https://s1.wklcdn.com/image_413/12390720/126457240/80787379.400x300.jpg',
      'Sandra Leal 2',
      'https://pt.wikiloc.com/trilhas-trekking/poco-das-meninas-cachoeiras-de-macacu-126457240',
    ),
  ],
  'cachoeira da chaleira fumaça': [
    _developmentPhoto(
      'https://s0.wklcdn.com/image_495/14869732/234733187/140006295.700x525.jpg',
      'Catharina_Koch',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-da-chaleira-fumaca-santa-fe-cachoeiras-de-macacu-rj-234733186',
    ),
    _developmentPhoto(
      'https://s1.wklcdn.com/image_495/14869732/234733188/140006296Master.jpg',
      'Catharina_Koch',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-da-chaleira-fumaca-santa-fe-cachoeiras-de-macacu-rj-234733186',
    ),
  ],
  'cachoeira da chaleira fumaca': [
    _developmentPhoto(
      'https://s0.wklcdn.com/image_495/14869732/234733187/140006295.700x525.jpg',
      'Catharina_Koch',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-da-chaleira-fumaca-santa-fe-cachoeiras-de-macacu-rj-234733186',
    ),
    _developmentPhoto(
      'https://s1.wklcdn.com/image_495/14869732/234733188/140006296Master.jpg',
      'Catharina_Koch',
      'https://pt.wikiloc.com/trilhas-trekking/cachoeira-da-chaleira-fumaca-santa-fe-cachoeiras-de-macacu-rj-234733186',
    ),
  ],
  'cachoeira santa fé': [
    _developmentPhoto(
      'https://trilhasecachoeiras-rj.weebly.com/uploads/4/0/0/7/40075427/7395293_orig.jpg',
      'Trilhas e Cachoeiras - RJ',
      'https://trilhasecachoeiras-rj.weebly.com/cachoeira-santa-feacute.html',
    ),
  ],
  'cachoeira santa fe': [
    _developmentPhoto(
      'https://trilhasecachoeiras-rj.weebly.com/uploads/4/0/0/7/40075427/7395293_orig.jpg',
      'Trilhas e Cachoeiras - RJ',
      'https://trilhasecachoeiras-rj.weebly.com/cachoeira-santa-feacute.html',
    ),
  ],
};

TouristSpotPhotoCredit _developmentPhoto(
  String url,
  String author,
  String sourceUrl,
) => TouristSpotPhotoCredit(
  url: url,
  author: author,
  license: 'Direitos não verificados · prévia de desenvolvimento',
  sourceUrl: sourceUrl,
  licenseUrl: '',
);

String _normalizeTouristTitle(String title) =>
    title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[-/.,()]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

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
