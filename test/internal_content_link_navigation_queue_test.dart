import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/navigation/internal_content_link.dart';
import 'package:tudo_aqui_macacu/core/navigation/internal_content_link_navigation_queue.dart';

void main() {
  const first = InternalContentLink(
    type: InternalContentType.establishment,
    id: 'business-1',
  );
  const second = InternalContentLink(
    type: InternalContentType.tourism,
    id: 'spot-2',
  );

  test(
    'coalesces duplicate intents and opens distinct links in arrival order',
    () async {
      final firstRoutePopped = Completer<void>();
      final opened = <InternalContentLink?>[];
      final queue = InternalContentLinkNavigationQueue(
        isActive: () => true,
        open: (link) {
          opened.add(link);
          return link == first ? firstRoutePopped.future : Future<void>.value();
        },
      );

      final draining = queue.enqueue(first);
      await Future<void>.delayed(Duration.zero);
      final repeatedFirst = queue.enqueue(first);
      final queuedSecond = queue.enqueue(second);
      final repeatedSecond = queue.enqueue(second);

      expect(opened, [first]);
      firstRoutePopped.complete();
      await Future.wait([
        draining,
        repeatedFirst,
        queuedSecond,
        repeatedSecond,
      ]);

      expect(opened, [first, second]);
    },
  );

  test('continues to the next link after a route opener fails', () async {
    final opened = <InternalContentLink?>[];
    final errors = <Object>[];
    final queue = InternalContentLinkNavigationQueue(
      isActive: () => true,
      open: (link) async {
        opened.add(link);
        if (link == first) throw StateError('navigation failed');
      },
      onOpenError: errors.add,
    );

    final firstDrain = queue.enqueue(first);
    final secondDrain = queue.enqueue(second);
    await Future.wait([firstDrain, secondDrain]);

    expect(opened, [first, second]);
    expect(errors, hasLength(1));
  });

  test('does not open queued links after its owner is disposed', () async {
    final opened = <InternalContentLink?>[];
    final hold = Completer<void>();
    final queue = InternalContentLinkNavigationQueue(
      isActive: () => true,
      open: (link) {
        opened.add(link);
        return hold.future;
      },
    );

    final draining = queue.enqueue(first);
    await Future<void>.delayed(Duration.zero);
    final queued = queue.enqueue(second);
    queue.dispose();
    hold.complete();
    await Future.wait([draining, queued]);

    expect(opened, [first]);
  });
}
