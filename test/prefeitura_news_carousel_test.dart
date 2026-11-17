import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/models/city_news_item.dart';
import 'package:tudo_aqui_macacu/features/home/services/city_news_repository.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/prefeitura_news_carousel.dart';

class _NewsRepository implements CityNewsRepository {
  _NewsRepository(this.snapshot);

  final CityNewsSnapshot? snapshot;
  @override
  bool get isAvailable => snapshot != null;
  @override
  Future<CityNewsSnapshot> load({bool forceRefresh = false}) async {
    if (snapshot == null) throw StateError('unavailable');
    return snapshot!;
  }
}

void main() {
  testWidgets('shows attributed Prefeitura article cards from the RSS feed', (
    tester,
  ) async {
    final repository = _NewsRepository(
      CityNewsSnapshot(
        source: 'Prefeitura de Cachoeiras de Macacu',
        profileUrl: Uri.https('www.prefeituracachoeiras.com', '/noticias'),
        posts: [
          CityNewsItem(
            id: 'post-1',
            title: 'Aviso importante da Prefeitura',
            caption: 'Confira os detalhes no portal.',
            imageUrl: 'https://static.wixstatic.com/media/post.jpg',
            permalink: Uri.https('www.prefeituracachoeiras.com', '/post/aviso'),
            publishedAt: DateTime.utc(2026, 11, 15),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrefeituraNewsCarousel(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aviso importante da Prefeitura'), findsOneWidget);
    expect(find.text('Notícias oficiais da Prefeitura'), findsOneWidget);
    expect(find.text('Ver todas'), findsOneWidget);
  });

  testWidgets(
    'keeps the official Prefeitura news link when the feed is disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrefeituraNewsCarousel(repository: _NewsRepository(null)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notícias da Prefeitura'), findsOneWidget);
      expect(
        find.text('Feed de notícias indisponível no momento.'),
        findsOneWidget,
      );
    },
  );
}
