import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/news/models/public_news_article.dart';

void main() {
  test('parses only public fields and the server timestamp wrapper', () {
    final article = PublicNewsArticle.fromMap({
      'id': 'news-original-id',
      'title': 'Notícia pública',
      'description': 'Conteúdo completo.',
      'category': 'Cidade',
      'imageUrl': 'https://images.example.invalid/cover.jpg',
      'additionalInfo': 'Informação pública complementar.',
      'publishedAt': {
        '_publicTimestamp': [1791504000, 123000000],
      },
      'targetEmail': 'private@example.invalid',
      'adminNotes': 'private',
    });

    expect(article.id, 'news-original-id');
    expect(article.title, 'Notícia pública');
    expect(article.description, 'Conteúdo completo.');
    expect(article.category, 'Cidade');
    expect(article.imageUrl, 'https://images.example.invalid/cover.jpg');
    expect(
      article.date,
      DateTime.fromMillisecondsSinceEpoch(1791504000123, isUtc: true),
    );
    expect(article.toString(), isNot(contains('private@example.invalid')));
  });

  test('accepts Firestore timestamps and tolerates optional fields', () {
    final article = PublicNewsArticle.fromMap({
      'id': 'article',
      'title': 'Título',
      'description': 'Texto',
      'date': Timestamp.fromDate(DateTime.utc(2026, 10, 9)),
    });
    expect(article.date?.toUtc(), DateTime.utc(2026, 10, 9));
    expect(article.category, isEmpty);
    expect(article.imageUrl, isEmpty);
    expect(article.additionalInfo, isEmpty);
  });

  test('rejects invalid identity or missing title', () {
    for (final data in [
      {'id': '', 'title': 'Título'},
      {'id': 'news/private', 'title': 'Título'},
      {'id': 'article', 'title': ''},
      {'id': 'article', 'title': 17},
    ]) {
      expect(() => PublicNewsArticle.fromMap(data), throwsFormatException);
    }
  });
}
