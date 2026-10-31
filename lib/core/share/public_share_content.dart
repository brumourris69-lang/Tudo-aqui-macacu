/// A deliberately small, public-only payload for the operating-system share UI.
///
/// Callers should pass only fields already approved for public display. The
/// builder never adds contact details, locations, internal IDs, or credentials.
class PublicShareContent {
  const PublicShareContent({
    required this.title,
    this.description = '',
    this.publicUrl = '',
  });

  final String title;
  final String description;

  /// An existing public HTTPS URL, if the app has one. Empty means no link is
  /// configured; this class does not synthesize routes or domains.
  final String publicUrl;

  bool get hasInvalidPublicUrl =>
      publicUrl.trim().isNotEmpty && _safePublicUri(publicUrl) == null;

  String get message {
    final safeTitle = _singleLine(title, limit: 120);
    if (safeTitle.isEmpty) {
      throw const FormatException('Conteúdo sem título para compartilhar.');
    }

    final safeDescription = _singleLine(description, limit: 220);
    final uri = _safePublicUri(publicUrl);
    return [
      safeTitle,
      if (safeDescription.isNotEmpty) safeDescription,
      if (uri != null) uri.toString() else 'Encontre no app Tudo Aqui Macacu.',
    ].join('\n');
  }
}

String _singleLine(String value, {required int limit}) {
  final normalized = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ');
  final compact = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= limit) return compact;
  return '${compact.substring(0, limit - 1).trimRight()}…';
}

Uri? _safePublicUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
