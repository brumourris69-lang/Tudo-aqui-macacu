import 'dart:async';
import 'dart:collection';

import 'internal_content_link.dart';

typedef InternalContentPageOpener =
    Future<void> Function(InternalContentLink? link);

/// Serializes received links so duplicate intents cannot stack duplicate pages.
class InternalContentLinkNavigationQueue {
  InternalContentLinkNavigationQueue({
    required bool Function() isActive,
    required InternalContentPageOpener open,
    void Function(Object error)? onOpenError,
  }) : _isActive = isActive,
       _open = open,
       _onOpenError = onOpenError;

  final bool Function() _isActive;
  final InternalContentPageOpener _open;
  final void Function(Object error)? _onOpenError;
  final Queue<InternalContentLink?> _pending = Queue();

  InternalContentLink? _active;
  bool _hasActive = false;
  bool _disposed = false;
  Future<void>? _draining;

  Future<void> enqueue(InternalContentLink? link) {
    if (_disposed || !_isActive()) return Future<void>.value();
    if ((_hasActive && link == _active) || _pending.contains(link)) {
      return _draining ?? Future<void>.value();
    }
    _pending.addLast(link);
    final current = _draining;
    if (current != null) return current;
    final draining = Future<void>.microtask(_drain);
    _draining = draining;
    return draining;
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && _isActive() && _pending.isNotEmpty) {
        final link = _pending.removeFirst();
        _active = link;
        _hasActive = true;
        try {
          await _open(link);
        } catch (error) {
          try {
            _onOpenError?.call(error);
          } catch (_) {
            // Reporting a navigation error must not strand later links.
          }
        } finally {
          _active = null;
          _hasActive = false;
        }
      }
    } finally {
      _draining = null;
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
