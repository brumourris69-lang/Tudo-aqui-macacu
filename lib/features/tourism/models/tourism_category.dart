class TourismCategory {
  const TourismCategory(this.key, this.name, this.description);

  final String key, name, description;

  static const values = [
    TourismCategory('cachoeiras', 'Cachoeiras', 'Explore por categoria'),
    TourismCategory('trilhas', 'Trilhas', 'Explore por categoria'),
    TourismCategory(
      'pontos_turisticos',
      'Pontos turísticos',
      'Explore por categoria',
    ),
    TourismCategory('roteiros', 'Roteiros', 'Explore por categoria'),
  ];

  static String normalize(String value) {
    final text = value.trim().toLowerCase();
    if (text.contains('cachoeira')) return 'cachoeiras';
    if (text.contains('trilha')) return 'trilhas';
    if (text.contains('roteiro') || text.contains('route')) return 'roteiros';
    if (text.contains('ponto') ||
        text.contains('turistico') ||
        text.contains('turístico') ||
        text.contains('atrativo') ||
        text.contains('hist')) {
      return 'pontos_turisticos';
    }
    return text;
  }
}
