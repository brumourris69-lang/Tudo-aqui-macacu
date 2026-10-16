const homeWaterfallBackgroundAsset =
    'assets/images/home-bg-waterfall-brand.png';

const defaultHomeOrder = [
  'banner',
  'categories',
  'highlights',
  'offers',
  'resources',
  'jobs',
  'events',
  'tourism',
];

class Category {
  const Category(this.name, this.artwork, this.types);
  final String name;
  final int artwork;
  final List<String> types;
}

class HomePageConfig {
  HomePageConfig.fromMap(Map<String, dynamic> data)
    : data = _homePageDataWithDefaults(data),
      sections = Map<String, dynamic>.from(data['sections'] ?? const {}),
      titles = Map<String, dynamic>.from(data['sectionTitles'] ?? const {}),
      limits = Map<String, dynamic>.from(data['sectionLimits'] ?? const {}),
      visual = _homeVisualWithDefaults(data['visual']),
      order = _stringList(data['sectionOrder']).isEmpty
          ? defaultHomeOrder
          : _stringList(data['sectionOrder']);

  final Map<String, dynamic> data, sections, titles, limits, visual;
  final List<String> order;

  static List<String> _stringList(dynamic value) =>
      value is List ? value.map((item) => item.toString()).toList() : const [];

  bool enabled(String section) => sections[section] != false;

  int limitFor(String section) =>
      ((limits[section] as num?)?.toInt() ??
              (section == 'categories'
                  ? 12
                  : section == 'highlights'
                  ? 6
                  : 2))
          .clamp(1, 12);

  String titleFor(String section) =>
      (titles[section] ?? _defaults[section] ?? section).toString();

  String get heroTitle =>
      (data['heroTitle'] ?? 'O que você procura hoje?').toString();

  String get searchPlaceholder =>
      (data['searchPlaceholder'] ?? 'Encontre em Macacu...').toString();

  String get slogan => (visual['slogan'] ?? 'A cidade na sua mão.').toString();

  String get greeting =>
      (visual['greeting'] ?? 'A cidade na sua mão.').toString();

  String get location =>
      (visual['location'] ?? 'Cachoeiras de Macacu • RJ').toString();

  String get logoUrl => (visual['logoUrl'] ?? '').toString();

  String get eventAgendaTitle =>
      (titles['eventsAgenda'] ?? 'Agenda Macacu').toString();

  String get backgroundType {
    final type = (visual['backgroundType'] ?? 'image').toString().trim();
    if (type == 'image' || type == 'gradient' || type == 'color') return type;
    return 'image';
  }

  String get backgroundImageUrl {
    final value = (visual['backgroundImageUrl'] ?? '').toString().trim();
    return value.isEmpty ? homeWaterfallBackgroundAsset : value;
  }

  String get backgroundStart =>
      (visual['backgroundStart'] ?? 'EAF4FF').toString();

  String get backgroundEnd => (visual['backgroundEnd'] ?? 'F8FAFC').toString();

  static const primaryCategoryNames = <String>[
    'Comércio',
    'Onde comer?',
    'Serviços',
    'Profissionais',
    'Empregos',
    'Turismo',
    'Serviços úteis',
    'Eventos',
  ];

  /// Returns the approved Home shortcuts while retaining the configured
  /// relative order and the original category objects used for routing.
  List<Category> primaryCategories(List<Category> source) {
    final ordered = categories(source);
    final byName = {for (final category in ordered) category.name: category};
    final configuredOrder = _stringList(data['categoryOrder']);
    if (configuredOrder.isEmpty) {
      return primaryCategoryNames
          .map((name) => byName[name])
          .whereType<Category>()
          .toList(growable: false);
    }
    final selected = <Category>[];
    final included = <String>{};
    for (final name in configuredOrder) {
      if (!primaryCategoryNames.contains(name) || !included.add(name)) {
        continue;
      }
      final category = byName[name];
      if (category != null) selected.add(category);
    }
    for (final name in primaryCategoryNames) {
      if (!included.add(name)) continue;
      final category = byName[name];
      if (category != null) selected.add(category);
    }
    return selected.toList(growable: false);
  }

  List<Category> categories(List<Category> source) {
    final names = _stringList(data['categoryOrder']);
    final icons = Map<String, dynamic>.from(data['categoryIcons'] ?? const {});
    final index = {for (var i = 0; i < names.length; i++) names[i]: i};
    final copy = source.indexed
        .map(
          (entry) => (
            sourceIndex: entry.$1,
            category: Category(
              entry.$2.name,
              (icons[entry.$2.name] as num?)?.toInt() ?? entry.$2.artwork,
              entry.$2.types,
            ),
          ),
        )
        .toList();
    copy.sort((a, b) {
      final configured = (index[a.category.name] ?? 999).compareTo(
        index[b.category.name] ?? 999,
      );
      return configured != 0 ? configured : a.sourceIndex.compareTo(b.sourceIndex);
    });
    return copy.map((entry) => entry.category).toList(growable: false);
  }

  static const _defaults = {
    'categories': 'Categorias',
    'highlights': 'Tá bombando em Macacu 🔥',
    'offers': 'Ofertas em Macacu',
    'resources': 'Cupons em Macacu',
    'jobs': 'Novos por aqui',
    'events': 'O que tá rolando',
    'tourism': 'Descubra Macacu',
  };
}

Map<String, dynamic> _homePageDataWithDefaults(Map<String, dynamic> data) => {
  ...data,
  'visual': _homeVisualWithDefaults(data['visual']),
};

Map<String, dynamic> _homeVisualWithDefaults(dynamic visual) {
  final map = visual is Map
      ? Map<String, dynamic>.from(visual)
      : const <String, dynamic>{};
  final type = (map['backgroundType'] ?? 'image').toString().trim();
  return {
    'slogan': 'A cidade na sua mão.',
    'greeting': 'A cidade na sua mão.',
    'location': 'Cachoeiras de Macacu • RJ',
    'logoUrl': '',
    'backgroundStart': 'EAF4FF',
    'backgroundEnd': 'F8FAFC',
    'backgroundImageUrl': homeWaterfallBackgroundAsset,
    ...map,
    'backgroundType': type == 'image' || type == 'gradient' || type == 'color'
        ? type
        : 'image',
  };
}

Map<String, dynamic> mergeHomePageData(
  Map<String, dynamic> published,
  Map<String, dynamic> draft,
) {
  final merged = <String, dynamic>{...published, ...draft};
  merged['visual'] = _homeVisualWithDefaults({
    ..._homeVisualWithDefaults(published['visual']),
    ..._homeMapValue(draft['visual']),
  });
  for (final key in ['sections', 'sectionTitles', 'sectionLimits']) {
    merged[key] = {
      ..._homeMapValue(published[key]),
      ..._homeMapValue(draft[key]),
    };
  }
  return merged;
}

Map<String, dynamic> _homeMapValue(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
