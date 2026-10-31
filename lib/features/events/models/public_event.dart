import '../utils/city_calendar_date.dart';

class PublicEvent {
  const PublicEvent({
    required this.id,
    required this.title,
    this.description = '',
    this.category = '',
    this.eventDate = '',
    this.endDate = '',
    this.location = '',
    this.imageUrl = '',
    this.address = '',
    this.maps = '',
    this.startTime = '',
    this.endTime = '',
    this.organizer = '',
    this.registrationUrl = '',
    this.contactUrl = '',
    this.galleryUrls = const [],
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String eventDate;
  final String endDate;
  final String location;
  final String imageUrl;
  final String address;
  final String maps;
  final String startTime;
  final String endTime;
  final String organizer;
  final String registrationUrl;
  final String contactUrl;
  final List<String> galleryUrls;

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
      final date = dateInBrasilia(value);
      if (date != null) {
        final day = date.day.toString().padLeft(2, '0');
        final month = date.month.toString().padLeft(2, '0');
        final year = date.year.toString();
        if (date.hour == 0 && date.minute == 0) return '$day/$month/$year';
        final hour = date.hour.toString().padLeft(2, '0');
        final minute = date.minute.toString().padLeft(2, '0');
        return '$day/$month/$year às $hour:$minute';
      }
      throw const FormatException('Data pública do evento inválida.');
    }

    final rawGallery = data['galleryUrls'];
    if (rawGallery != null && rawGallery is! List) {
      throw const FormatException('Galeria pública do evento inválida.');
    }
    final gallery = <String>[];
    for (final value in (rawGallery as List?) ?? const []) {
      if (value is! String) {
        throw const FormatException('Galeria pública do evento inválida.');
      }
      final uri = Uri.tryParse(value.trim());
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          gallery.length < 20) {
        gallery.add(value.trim());
      }
    }

    return PublicEvent(
      id: id,
      title: title,
      description: optionalText('description'),
      category: optionalText('category'),
      eventDate: eventDateLabel(data['eventDate']),
      endDate: eventDateLabel(data['endDate']),
      location: optionalText('location'),
      imageUrl: optionalText('imageUrl'),
      address: optionalText('address'),
      maps: optionalText('maps') == ''
          ? optionalText('mapsUrl')
          : optionalText('maps'),
      startTime: optionalText('startTime'),
      endTime: optionalText('endTime'),
      organizer: optionalText('organizer'),
      registrationUrl: optionalText('registrationUrl'),
      contactUrl: optionalText('contactUrl'),
      galleryUrls: List.unmodifiable(gallery),
    );
  }
}
