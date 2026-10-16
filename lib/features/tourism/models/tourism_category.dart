class TourismCategory {
  const TourismCategory(this.key, this.name, this.description);

  final String key, name, description;

  static const values = [
    TourismCategory(
      'pontos_turisticos',
      'Pontos turísticos',
      'Explore por categoria',
    ),
    TourismCategory('trilhas', 'Trilhas', 'Explore por categoria'),
    TourismCategory(
      'guias_turisticos',
      'Guias turísticos',
      'Explore por categoria',
    ),
    TourismCategory(
      'historia_cidade',
      'História da cidade',
      'Explore por categoria',
    ),
  ];

  static String normalize(String value) {
    final text = value.trim().toLowerCase();
    // Check specific category names before broad "turístico" matching so
    // `guias_turisticos` does not get reclassified as a tourist spot.
    if (text.contains('roteiro') || text.contains('route')) return 'roteiros';
    if (text.contains('guia') || text.contains('guide')) {
      return 'guias_turisticos';
    }
    if (text.contains('hist') || text.contains('history')) {
      return 'historia_cidade';
    }
    if (text.contains('cachoeira') ||
        text.contains('ponto') ||
        text.contains('turistico') ||
        text.contains('turístico') ||
        text.contains('atrativo')) {
      return 'pontos_turisticos';
    }
    if (text.contains('trilha')) return 'trilhas';
    return text;
  }
}
