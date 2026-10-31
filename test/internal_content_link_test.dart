import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tudo_aqui_macacu/core/navigation/incoming_content_link_page.dart';
import 'package:tudo_aqui_macacu/core/navigation/internal_content_link.dart';
import 'package:tudo_aqui_macacu/core/navigation/internal_content_link_service.dart';
import 'package:tudo_aqui_macacu/core/navigation/public_content_link_resolver.dart';

void main() {
  group('InternalContentLink', () {
    test('parses the supported content types and preserves stable IDs', () {
      expect(
        InternalContentLink.parse('tudoaqui://content/establishment/modelo-42'),
        const InternalContentLink(
          type: InternalContentType.establishment,
          id: 'modelo-42',
        ),
      );
      expect(
        InternalContentLink.parse('tudoaqui://content/tourism/spot_7'),
        const InternalContentLink(
          type: InternalContentType.tourism,
          id: 'spot_7',
        ),
      );
      expect(
        InternalContentLink.parse('tudoaqui://content/event/event-2026'),
        const InternalContentLink(
          type: InternalContentType.event,
          id: 'event-2026',
        ),
      );
    });

    test('creates only an internal URI, without a public web domain', () {
      final uri = const InternalContentLink(
        type: InternalContentType.establishment,
        id: 'modelo-42',
      ).toUri();

      expect(uri.scheme, 'tudoaqui');
      expect(uri.host, 'content');
      expect(uri.pathSegments, ['establishment', 'modelo-42']);
      expect(uri.hasQuery, isFalse);
      expect(uri.hasFragment, isFalse);
    });

    test('rejects malformed, unsupported, or traversal-like links', () {
      for (final value in <String?>[
        null,
        '',
        'https://example.test/establishment/modelo-42',
        'tudoaqui://other/establishment/modelo-42',
        'tudoaqui://content/unknown/modelo-42',
        'tudoaqui://content/establishment/',
        'tudoaqui://content/establishment/../secret',
        'tudoaqui://content/establishment/a%2Fb',
        'tudoaqui://content/establishment/modelo-42/extra',
        'tudoaqui://user@content/event/event-2026',
        'tudoaqui://content/event/event-2026?draft=true',
        'tudoaqui://content/event/event-2026#private',
      ]) {
        expect(InternalContentLink.parse(value), isNull, reason: '$value');
      }
    });
  });

  group('PublicContentLinkResolver', () {
    test('maps each internal type to its existing public collection', () async {
      final calls = <Map<String, dynamic>>[];
      final resolver = PublicContentLinkResolver(
        resolve: ({required collection, required id}) async {
          calls.add({'collection': collection, 'id': id});
          return null;
        },
      );

      for (final type in InternalContentType.values) {
        await resolver.resolve(
          InternalContentLink(type: type, id: 'stable-id'),
        );
      }

      expect(calls, [
        {'collection': 'establishments', 'id': 'stable-id'},
        {'collection': 'routes', 'id': 'stable-id'},
        {'collection': 'events', 'id': 'stable-id'},
      ]);
    });

    test('returns unavailable without exposing hidden document data', () async {
      final resolver = PublicContentLinkResolver(
        resolve: ({required collection, required id}) async => null,
      );

      expect(
        await resolver.resolve(
          const InternalContentLink(
            type: InternalContentType.establishment,
            id: 'stable-id',
          ),
        ),
        isNull,
      );
    });
  });

  group('IncomingContentLinkPage', () {
    const link = InternalContentLink(
      type: InternalContentType.event,
      id: 'event-1',
    );

    testWidgets('opens the resolved public detail page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => IncomingContentLinkPage(
                      link: link,
                      resolvePage: (_) async => Scaffold(
                        appBar: AppBar(title: const Text('Detalhe público')),
                        body: const Text('Conteúdo carregado'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Home'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('Conteúdo carregado'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('shows unavailable when the public resolver returns null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingContentLinkPage(
            link: link,
            resolvePage: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Este conteúdo não está disponível.'), findsOneWidget);
    });

    testWidgets('shows invalid link without invoking a resolver', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingContentLinkPage(
            link: null,
            resolvePage: (_) async {
              called = true;
              return null;
            },
          ),
        ),
      );

      expect(find.text('Este link não é válido.'), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('offers retry after a public-service error', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: IncomingContentLinkPage(
            link: link,
            resolvePage: (_) async {
              calls++;
              if (calls == 1) throw StateError('temporary failure');
              return const Scaffold(body: Text('Conteúdo recuperado'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar este conteúdo.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(find.text('Conteúdo recuperado'), findsOneWidget);
      expect(calls, 2);
    });
  });

  group('InternalContentLinkService', () {
    test('drains cold and warm links, reporting invalid URIs safely', () async {
      final transport = _FakeLinkTransport([
        'tudoaqui://content/tourism/spot-1',
        'tudoaqui://content/unsupported/nope',
      ]);
      final service = InternalContentLinkService(transport: transport);
      final received = <InternalContentLink?>[];
      final subscription = service.links.listen(received.add);

      await service.start();
      await Future<void>.delayed(Duration.zero);
      transport.pending.add('tudoaqui://content/event/event-2');
      await transport.listener!();
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        const InternalContentLink(
          type: InternalContentType.tourism,
          id: 'spot-1',
        ),
        null,
        const InternalContentLink(
          type: InternalContentType.event,
          id: 'event-2',
        ),
      ]);
      expect(transport.listener, isNotNull);
      await subscription.cancel();
    });

    test('does not lose an intent arriving during a pending drain', () async {
      final transport = _BlockingLinkTransport();
      final service = InternalContentLinkService(transport: transport);
      final received = <InternalContentLink?>[];
      final subscription = service.links.listen(received.add);

      final startup = service.start();
      await Future<void>.delayed(Duration.zero);
      transport.pending.add('tudoaqui://content/event/warm-event');
      await transport.listener!();
      transport.release.complete();
      await startup;
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        const InternalContentLink(
          type: InternalContentType.event,
          id: 'warm-event',
        ),
      ]);
      await subscription.cancel();
    });

    test(
      'buffers the cold-start intent until the app shell subscribes',
      () async {
        final transport = _FakeLinkTransport([
          'tudoaqui://content/establishment/modelo-cold',
        ]);
        final service = InternalContentLinkService(transport: transport);

        await service.start();
        final received = <InternalContentLink?>[];
        final subscription = service.links.listen(received.add);
        await Future<void>.delayed(Duration.zero);

        expect(received, [
          const InternalContentLink(
            type: InternalContentType.establishment,
            id: 'modelo-cold',
          ),
        ]);
        await subscription.cancel();
      },
    );

    test('buffers links received while no shell listener is mounted', () async {
      final transport = _FakeLinkTransport([]);
      final service = InternalContentLinkService(transport: transport);
      final firstSubscription = service.links.listen((_) {});
      await service.start();
      await firstSubscription.cancel();

      transport.pending.add('tudoaqui://content/event/from-background');
      await transport.listener!();
      final received = <InternalContentLink?>[];
      final secondSubscription = service.links.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        const InternalContentLink(
          type: InternalContentType.event,
          id: 'from-background',
        ),
      ]);
      await secondSubscription.cancel();
    });
  });
}

class _FakeLinkTransport implements InternalContentLinkTransport {
  _FakeLinkTransport(this.pending);

  final List<Object?> pending;
  Future<void> Function()? listener;

  @override
  Future<List<Object?>> takePendingLinks() async {
    final result = List<Object?>.of(pending);
    pending.clear();
    return result;
  }

  @override
  void setPendingLinksListener(Future<void> Function() listener) {
    this.listener = listener;
  }
}

class _BlockingLinkTransport implements InternalContentLinkTransport {
  final List<Object?> pending = [];
  final Completer<void> release = Completer<void>();
  Future<void> Function()? listener;
  bool _first = true;

  @override
  Future<List<Object?>> takePendingLinks() async {
    final result = List<Object?>.of(pending);
    pending.clear();
    if (_first) {
      _first = false;
      await release.future;
    }
    return result;
  }

  @override
  void setPendingLinksListener(Future<void> Function() listener) {
    this.listener = listener;
  }
}
