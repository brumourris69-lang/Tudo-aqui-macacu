class PublicEvent {
  const PublicEvent({
    required this.id,
    required this.title,
    this.description = '',
    this.category = '',
    this.eventDate = '',
    this.location = '',
    this.imageUrl = '',
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String eventDate;
  final String location;
  final String imageUrl;

  factory PublicEvent.fromMap(Map<dynamic, dynamic> data) {
    final id = data['id'];
    final title = data['title'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.contains('/') ||
        title is! String ||
        title.trim().isEmpty) {
      throw const FormatException('Evento público inválido.');
    }

    String optionalText(String key) {
      final value = data[key];
      if (value == null) return '';
      if (value is! String) {
        throw const FormatException('Campo público do evento inválido.');
      }
      return value;
    }

    String eventDateLabel(Object? value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is Map &&
          value.length == 1 &&
          value['_publicTimestamp'] is List) {
        final parts = value['_publicTimestamp'] as List;
        if (parts.length == 2 && parts.every((part) => part is int)) {
          final date = DateTime.fromMillisecondsSinceEpoch(
            (parts[0] as int) * 1000 + (parts[1] as int) ~/ 1000000,
            isUtc: true,
          ).toLocal();
          final day = date.day.toString().padLeft(2, '0');
          final month = date.month.toString().padLeft(2, '0');
          final year = date.year.toString();
          if (date.hour == 0 && date.minute == 0) return '$day/$month/$year';
          final hour = date.hour.toString().padLeft(2, '0');
          final minute = date.minute.toString().padLeft(2, '0');
          return '$day/$month/$year às $hour:$minute';
        }
      }
      throw const FormatException('Data pública do evento inválida.');
    }

    return PublicEvent(
      id: id,
      title: title,
      description: optionalText('description'),
      category: optionalText('category'),
      eventDate: eventDateLabel(data['eventDate']),
      location: optionalText('location'),
      imageUrl: optionalText('imageUrl'),
    );
  }
}
