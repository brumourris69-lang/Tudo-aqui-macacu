bool isAllowedExternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return uri.host.trim().isNotEmpty;
  if (scheme == 'tel') return uri.path.trim().isNotEmpty;
  if (scheme == 'mailto') return uri.path.contains('@');
  if (scheme == 'whatsapp') return true;
  if (scheme == 'geo') return uri.path.trim().isNotEmpty;
  return false;
}
