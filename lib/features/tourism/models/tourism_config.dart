import '../../../core/media/media_url_service.dart';
import 'tourism_category.dart';

class TourismConfig {
  TourismConfig.fromMap(Map<String, dynamic> data)
    : title = (data['title'] ?? 'Explore Macacu').toString(),
      subtitle = (data['subtitle'] ?? 'Explore por categoria').toString(),
      imageUrl = cloudinaryOptimizedImageUrl(
        (data['imageUrl'] ?? '').toString(),
      ),
      categories = [
        for (final category in TourismCategory.values)
          TourismCategoryConfig.fromMap(
            category,
            _categoryConfig(data, category.key),
          ),
      ] {
    categories.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
  }

  final String title, subtitle, imageUrl;
  final List<TourismCategoryConfig> categories;

  Map<String, dynamic> toMap() => {
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'categories': {for (final c in categories) c.key: c.toMap()},
  };
}

Map<String, dynamic> _categoryConfig(Map<String, dynamic> data, String key) {
  final categories = data['categories'];
  if (categories is! Map) return const {};
  final current = categories[key];
  if (current is Map) return Map<String, dynamic>.from(current);
  if (key == 'pontos_turisticos' && categories['cachoeiras'] is Map) {
    return Map<String, dynamic>.from(categories['cachoeiras'] as Map)
      ..remove('name');
  }
  final legacyKeys = switch (key) {
    'pontos_turisticos' => [
      'cachoeiras_pocos_lagoas',
      'parques_reservas',
      'roteiros_turisticos',
      'roteiros',
      'mirantes',
    ],
    'trilhas' => ['trilhas_montanhas'],
    'historia_cidade' => ['historia_cultura'],
    _ => const <String>[],
  };
  final configured = [
    for (final legacyKey in legacyKeys)
      if (categories[legacyKey] is Map)
        Map<String, dynamic>.from(categories[legacyKey] as Map),
  ];
  if (configured.isNotEmpty) {
    // Subcategory settings feed the existing card without creating new cards.
    // Missing aliases retain the model's default-active behavior.
    final presentation = configured.first..remove('name');
    if (key == 'pontos_turisticos') {
      final allAliasesExplicitlyInactive = legacyKeys.every((legacyKey) {
        final config = categories[legacyKey];
        return config is Map && config['active'] == false;
      });
      presentation['active'] = !allAliasesExplicitlyInactive;
    }
    return presentation;
  }
  return const {};
}

class TourismCategoryConfig {
  TourismCategoryConfig.fromMap(
    TourismCategory category,
    Map<String, dynamic> data,
  ) : key = category.key,
      name = (data['name'] ?? category.name).toString(),
      description = (data['description'] ?? '').toString(),
      imageUrl = cloudinaryOptimizedImageUrl(
        (data['imageUrl'] ?? '').toString(),
      ),
      order = data['order'] is num
          ? (data['order'] as num).toInt()
          : TourismCategory.values.indexOf(category),
      active = data['active'] != false;

  final String key, name, description, imageUrl;
  final int order;
  final bool active;

  Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'imageUrl': imageUrl,
    'order': order,
    'active': active,
  };
}
