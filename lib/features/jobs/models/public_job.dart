/// Minimal public projection returned by the isolated jobs detail resolver.
/// Contact channels and application links are intentionally not represented.
class PublicJob {
  const PublicJob({
    required this.id,
    required this.title,
    this.description = '',
    this.category = '',
    this.location = '',
    this.company = '',
    this.employmentType = '',
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String location;
  final String company;
  final String employmentType;

  static void validateId(String id) {
    if (id.trim().isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw const FormatException('Vaga inválida.');
    }
  }

  static PublicJob? fromSearchResponse(
    dynamic value, {
    required String requestedId,
  }) {
    validateId(requestedId);
    if (value is! Map ||
        (value['status'] != 'available' && value['status'] != 'unavailable')) {
      throw const FormatException('Resposta de vaga inválida.');
    }
    if (value['status'] == 'unavailable') return null;
    if (value['id'] != requestedId || value['data'] is! Map) {
      throw const FormatException('Resposta de vaga inválida.');
    }
    return PublicJob.fromMap({
      ...Map<String, dynamic>.from(value['data'] as Map),
      'id': requestedId,
    });
  }

  factory PublicJob.fromMap(Map<dynamic, dynamic> data) {
    final id = data['id'];
    final title = data['title'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.contains('/') ||
        title is! String ||
        title.trim().isEmpty) {
      throw const FormatException('Vaga pública inválida.');
    }

    String optionalText(String key) {
      final value = data[key];
      if (value == null) return '';
      if (value is! String) {
        throw const FormatException('Campo público da vaga inválido.');
      }
      return value;
    }

    return PublicJob(
      id: id,
      title: title,
      description: optionalText('description'),
      category: optionalText('category'),
      location: optionalText('location'),
      company: optionalText('company'),
      employmentType: optionalText('employmentType'),
    );
  }
}
