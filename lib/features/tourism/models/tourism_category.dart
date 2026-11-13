class TourismCategory {
  const TourismCategory(this.key, this.name, this.description);

  final String key, name, description;

  /// The four existing public spaces in Explorar Macacu.
  ///
  /// Newer import classifications remain useful as internal subcategories,
  /// but must not create additional primary destinations in the app.
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

  /// Groups imported and legacy classifications under the existing spaces.
  /// This is a presentation mapping only; it does not rewrite stored records.
  static String normalize(String value) {
    final text = value.trim().toLowerCase();

    // Keep guides distinct before matching broad tourist/route terms.
    if (text.contains('guia') || text.contains('guide')) {
      return 'guias_turisticos';
    }
    if (text.contains('hist') ||
        text.contains('cultur') ||
        text.contains('history')) {
      return 'historia_cidade';
    }
    if (text.contains('trilha') ||
        text.contains('montanha') ||
        text.contains('trek')) {
      return 'trilhas';
    }
    if (text.contains('ponto') ||
        text.contains('turistico') ||
        text.contains('turístico') ||
        text.contains('cachoeira') ||
        text.contains('poço') ||
        text.contains('poco') ||
        text.contains('lagoa') ||
        text.contains('parque') ||
        text.contains('reserva') ||
        text.contains('roteiro') ||
        text.contains('route') ||
        text.contains('mirante') ||
        text.contains('viewpoint') ||
        text.contains('waterfall') ||
        text.contains('atrativo')) {
      return 'pontos_turisticos';
    }
    return text;
  }
}
