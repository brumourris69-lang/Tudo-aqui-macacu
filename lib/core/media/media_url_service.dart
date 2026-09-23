String normalizeImageUrl(String raw) {
  var value = raw.trim().replaceAll('&amp;', '&');
  if (value.isEmpty) return '';
  value = value.replaceAll(RegExp(r'''^["']+|["']+$'''), '');
  final urlMatch = RegExp(r'https?://\S+').firstMatch(value);
  if (urlMatch != null) value = urlMatch.group(0)!;
  value = value.replaceAll(RegExp(r'[\]\)>,.;]+$'), '');
  if (value.startsWith('http://res.cloudinary.com/')) {
    value = value.replaceFirst('http://', 'https://');
  }
  return value;
}

List<String> imageUrlsFromInput(String raw) {
  final candidates = raw.split(RegExp(r'\r?\n'));
  final seen = <String>{};
  return candidates
      .map(normalizeImageUrl)
      .where(
        (url) =>
            (url.startsWith('http://') || url.startsWith('https://')) &&
            seen.add(url),
      )
      .toList();
}

List<String> orderedUniqueImageUrls(Iterable<String> values) {
  final seen = <String>{};
  return values
      .map(cloudinaryOptimizedImageUrl)
      .where((url) => url.isNotEmpty && seen.add(url))
      .toList();
}

List<String> setCoverImageUrl(List<String> urls, int index) {
  if (index < 0 || index >= urls.length) return List<String>.from(urls);
  final next = List<String>.from(urls);
  final item = next.removeAt(index);
  next.insert(0, item);
  return next;
}

List<String> moveImageUrl(List<String> urls, int index, int direction) {
  final target = index + direction;
  if (index < 0 ||
      index >= urls.length ||
      target < 0 ||
      target >= urls.length) {
    return List<String>.from(urls);
  }
  final next = List<String>.from(urls);
  final item = next.removeAt(index);
  next.insert(target, item);
  return next;
}

List<String> removeImageUrl(List<String> urls, int index) {
  if (index < 0 || index >= urls.length) return List<String>.from(urls);
  return List<String>.from(urls)..removeAt(index);
}

String cloudinaryOptimizedImageUrl(String raw) {
  final value = normalizeImageUrl(raw);
  if (value.isEmpty || !value.contains('res.cloudinary.com')) return value;
  const marker = '/upload/';
  final index = value.indexOf(marker);
  if (index < 0) return value;
  final queryIndex = value.indexOf('?', index + marker.length);
  final fragmentIndex = value.indexOf('#', index + marker.length);
  final suffixStart = [queryIndex, fragmentIndex]
      .where((item) => item >= 0)
      .fold<int>(
        value.length,
        (previous, item) => item < previous ? item : previous,
      );
  final before = value.substring(0, index + marker.length);
  final after = value.substring(index + marker.length, suffixStart);
  final suffix = value.substring(suffixStart);
  if (after.startsWith('f_auto') || after.startsWith('q_auto')) return value;
  return '${before}f_auto,q_auto,w_1600,c_limit/$after$suffix';
}
