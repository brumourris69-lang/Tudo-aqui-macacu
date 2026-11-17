class CityNewsItem {
  const CityNewsItem({
    required this.id,
    required this.title,
    required this.caption,
    required this.imageUrl,
    required this.permalink,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String caption;
  final String? imageUrl;
  final Uri permalink;
  final DateTime? publishedAt;

  static CityNewsItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final caption = raw['caption'];
    final imageUrl = raw['imageUrl'];
    final permalink = raw['permalink'];
    final publishedAt = raw['timestamp'];
    final imageUri = imageUrl is String && imageUrl.isNotEmpty
        ? Uri.tryParse(imageUrl)
        : null;
    final linkUri = permalink is String ? Uri.tryParse(permalink) : null;
    final timestamp = publishedAt is String
        ? DateTime.tryParse(publishedAt)?.toUtc()
        : null;
    if (id is! String ||
        id.isEmpty ||
        id.length > 180 ||
        title is! String ||
        title.isEmpty ||
        caption is! String ||
        (imageUrl is! String) ||
        (imageUrl.isNotEmpty &&
            (imageUri == null ||
                !_httpsHost(imageUri, 'static.wixstatic.com'))) ||
        linkUri == null ||
        !_httpsHost(linkUri, 'www.prefeituracachoeiras.com')) {
      return null;
    }
    return CityNewsItem(
      id: id,
      title: title.substring(0, title.length > 180 ? 180 : title.length),
      caption: caption.substring(
        0,
        caption.length > 240 ? 240 : caption.length,
      ),
      imageUrl: imageUri?.toString(),
      permalink: linkUri,
      publishedAt: timestamp,
    );
  }

  static bool _httpsHost(Uri uri, String host) =>
      uri.scheme == 'https' && uri.userInfo.isEmpty && uri.host == host;
}
