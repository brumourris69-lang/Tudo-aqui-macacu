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
  if (key == 'guias_turisticos' && categories['roteiros'] is Map) {
    final legacy = Map<String, dynamic>.from(categories['roteiros'] as Map);
    // Old configuration only supplies appearance and visibility defaults. Its
    // custom Roteiros title remains the label of the legacy subsection.
    legacy.remove('name');
    return legacy;
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
