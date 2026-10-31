/// Content kinds accepted by the app's private, device-local link contract.
enum InternalContentType {
  establishment('establishment', 'establishments'),
  tourism('tourism', 'routes'),
  event('event', 'events');

  const InternalContentType(this.segment, this.publicCollection);

  final String segment;
  final String publicCollection;

  static InternalContentType? fromSegment(String value) {
    for (final type in values) {
      if (type.segment == value) return type;
    }
    return null;
  }
}

/// Stable internal destination. This URI is not a public web URL.
class InternalContentLink {
  const InternalContentLink({required this.type, required this.id});

  static const scheme = 'tudoaqui';
  static const host = 'content';
  static final _safeId = RegExp(r'^[A-Za-z0-9._~-]{1,150}$');

  final InternalContentType type;
  final String id;

  static InternalContentLink? parse(String? value) {
    if (value == null || value.isEmpty || value.length > 2048) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != scheme ||
        uri.host != host ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length != 2) return null;
    final type = InternalContentType.fromSegment(segments[0]);
    final id = segments[1];
    if (type == null || id == '.' || id == '..' || !_safeId.hasMatch(id)) {
      return null;
    }
    return InternalContentLink(type: type, id: id);
  }

  Uri toUri() =>
      Uri(scheme: scheme, host: host, pathSegments: [type.segment, id]);

  @override
  bool operator ==(Object other) =>
      other is InternalContentLink && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}
