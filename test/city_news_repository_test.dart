import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tudo_aqui_macacu/features/home/models/city_news_item.dart';
import 'package:tudo_aqui_macacu/features/home/services/city_news_repository.dart';

void main() {
  group('CityNewsItem', () {
    test('accepts only Prefeitura article and Wix image URLs', () {
      final item = CityNewsItem.tryParse({
        'id': 'item-1',
        'title': 'Aviso municipal',
        'caption': 'Resumo da notícia.',
        'imageUrl': 'https://static.wixstatic.com/media/notice.jpg',
        'permalink':
            'https://www.prefeituracachoeiras.com/post/aviso-municipal',
        'timestamp': '2026-11-15T10:00:00Z',
      });
      expect(item, isNotNull);
      expect(item!.publishedAt, DateTime.utc(2026, 11, 15, 10));
      expect(
        CityNewsItem.tryParse({
          'id': 'no-image',
          'title': 'Aviso sem foto',
          'caption': '',
          'imageUrl': '',
          'permalink': 'https://www.prefeituracachoeiras.com/post/aviso',
        })?.imageUrl,
        isNull,
      );
      expect(
        CityNewsItem.tryParse({
          'id': 'bad-image',
          'title': 'A',
          'caption': '',
          'imageUrl': 'https://attacker.invalid/image.jpg',
          'permalink': 'https://www.prefeituracachoeiras.com/post/a',
        }),
        isNull,
      );
      expect(
        CityNewsItem.tryParse({
          'id': 'bad-link',
          'title': 'A',
          'caption': '',
          'imageUrl': 'https://static.wixstatic.com/media/a.jpg',
          'permalink': 'https://attacker.invalid/post/a',
        }),
        isNull,
      );
    });
  });

  group('PrefeituraRssNewsRepository', () {
    const endpoint =
        'https://tudo-aqui-macacu-image-upload.tudo-aqui-macacu-image-upload.workers.dev/v1/city-news';
    test(
      'requires validated Spark distribution and the fixed Worker endpoint',
      () async {
        final notReady = PrefeituraRssNewsRepository(
          endpoint: endpoint,
          distributionReady: () => false,
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        expect(notReady.isAvailable, isFalse);
        expect(PrefeituraRssNewsRepository.endpointIsAllowed(endpoint), isTrue);
        for (final value in [
          'http://tudo-aqui-macacu-image-upload.tudo-aqui-macacu-image-upload.workers.dev/v1/city-news',
          'https://evil.example/v1/city-news',
          '$endpoint?url=https://attacker.invalid',
          'https://tudo-aqui-macacu-image-upload.tudo-aqui-macacu-image-upload.workers.dev/v1/other',
        ]) {
          expect(PrefeituraRssNewsRepository.endpointIsAllowed(value), isFalse);
        }
        await expectLater(notReady.load(), throwsStateError);
      },
    );

    test('loads the official feed and caches valid items', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.toString(), endpoint);
        return http.Response(
          jsonEncode({
            'source': 'Prefeitura de Cachoeiras de Macacu',
            'profileUrl': 'https://www.prefeituracachoeiras.com/noticias',
            'posts': [
              {
                'id': 'p1',
                'title': 'Aviso importante',
                'caption': 'Resumo publicado no portal.',
                'imageUrl': 'https://static.wixstatic.com/media/news.jpg',
                'permalink': 'https://www.prefeituracachoeiras.com/post/aviso',
                'timestamp': '2026-11-15T10:00:00Z',
              },
              {
                'id': 'bad',
                'title': 'Não confiar na imagem',
                'caption': '',
                'imageUrl': 'https://attacker.invalid/track',
                'permalink': 'https://www.prefeituracachoeiras.com/post/unsafe',
              },
            ],
          }),
          200,
        );
      });
      final repository = PrefeituraRssNewsRepository(
        endpoint: endpoint,
        client: client,
        distributionReady: () => true,
      );
      expect(repository.isAvailable, isTrue);
      final first = await repository.load();
      final second = await repository.load();
      expect(first.posts, hasLength(1));
      expect(first.posts.single.title, 'Aviso importante');
      expect(identical(first, second), isTrue);
      expect(requests, 1);
    });

    test(
      'fails closed on malformed source, failed response or missing endpoint',
      () async {
        final wrongSource = PrefeituraRssNewsRepository(
          endpoint: endpoint,
          distributionReady: () => true,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'source': 'another-site',
                'profileUrl': 'https://www.prefeituracachoeiras.com/noticias',
                'posts': [],
              }),
              200,
            ),
          ),
        );
        await expectLater(wrongSource.load(), throwsFormatException);

        final unavailable = PrefeituraRssNewsRepository(
          endpoint: endpoint,
          distributionReady: () => true,
          client: MockClient((_) async => http.Response('{}', 503)),
        );
        await expectLater(unavailable.load(), throwsFormatException);

        final disabled = PrefeituraRssNewsRepository(
          endpoint: '',
          distributionReady: () => true,
          client: MockClient((_) async => fail('must not call network')),
        );
        expect(disabled.isAvailable, isFalse);
        await expectLater(disabled.load(), throwsStateError);
      },
    );
  });
}
