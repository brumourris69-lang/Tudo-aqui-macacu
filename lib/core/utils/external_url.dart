bool isAllowedExternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') {
    return uri.host.trim().isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.host == uri.host.trim() &&
        !uri.host.contains(RegExp(r'[\s\\]'));
  }
  if (scheme == 'tel') {
    final digits = uri.path.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^\+?[\d(). -]+$').hasMatch(uri.path) &&
        digits.length >= 8 &&
        digits.length <= 15;
  }
  if (scheme == 'mailto') return uri.path.contains('@');
  if (scheme == 'whatsapp') return true;
  if (scheme == 'geo') return uri.path.trim().isNotEmpty;
  return false;
}
