/// Latin/Portuguese normalization shared by future query and content adapters.
/// This prepares words, not a Firestore full-text query or a prefix index.
String normalizeSearchText(String value) {
  var normalized = value.toLowerCase();
  const replacements = {
    'a': 'áàâãäå',
    'e': 'éèêë',
    'i': 'íìîï',
    'o': 'óòôõö',
    'u': 'úùûü',
    'c': 'ç',
    'n': 'ñ',
    'y': 'ýÿ',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
  }
  return normalized
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

List<String> prepareSearchTerms(String value) {
  final normalized = normalizeSearchText(value);
  return List.unmodifiable(
    normalized.isEmpty ? <String>[] : normalized.split(' ').toSet(),
  );
}
