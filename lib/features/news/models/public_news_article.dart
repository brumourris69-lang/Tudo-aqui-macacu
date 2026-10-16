import 'package:cloud_firestore/cloud_firestore.dart';

/// Public, allowlisted fields returned by the local news detail resolver.
class PublicNewsArticle {
  const PublicNewsArticle({
    required this.id,
    required this.title,
    required this.description,
    this.category = '',
    this.imageUrl = '',
    this.additionalInfo = '',
    this.date,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String imageUrl;
  final String additionalInfo;
  final DateTime? date;

  factory PublicNewsArticle.fromMap(Map<dynamic, dynamic> data) {
    final id = data['id'];
    final title = data['title'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.contains('/') ||
        title is! String ||
        title.trim().isEmpty) {
      throw const FormatException('Notícia pública inválida.');
    }

    String optionalText(String key) {
      final value = data[key];
      if (value == null) return '';
      if (value is! String) {
        throw const FormatException('Campo público da notícia inválido.');
      }
      return value;
    }

    DateTime? parseDate(Object? value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      if (value is Map &&
          value.length == 1 &&
          value['_publicTimestamp'] is List) {
        final parts = value['_publicTimestamp'] as List;
        if (parts.length == 2 && parts.every((part) => part is int)) {
          return DateTime.fromMillisecondsSinceEpoch(
            (parts[0] as int) * 1000 + (parts[1] as int) ~/ 1000000,
            isUtc: true,
          );
        }
      }
      return null;
    }

    return PublicNewsArticle(
      id: id,
      title: title,
      description: optionalText('description'),
      category: optionalText('category'),
      imageUrl: optionalText('imageUrl'),
      additionalInfo: optionalText('additionalInfo'),
      date: parseDate(data['publishedAt'] ?? data['date'] ?? data['createdAt']),
    );
  }
}
