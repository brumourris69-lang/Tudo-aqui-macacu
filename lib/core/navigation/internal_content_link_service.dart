import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import 'internal_content_link.dart';

abstract interface class InternalContentLinkTransport {
  void setPendingLinksListener(Future<void> Function() listener);

  Future<List<Object?>> takePendingLinks();
}

class MethodChannelInternalContentLinkTransport
    implements InternalContentLinkTransport {
  MethodChannelInternalContentLinkTransport({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('macacu/content-links');

  final MethodChannel _channel;

  @override
  void setPendingLinksListener(Future<void> Function() listener) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pendingContentLinks') await listener();
    });
  }

  @override
  Future<List<Object?>> takePendingLinks() async =>
      await _channel.invokeListMethod<Object?>('takePendingLinks') ??
      const <Object?>[];
}

/// Receives cold-start and warm-start Android intents from the native bridge.
class InternalContentLinkService {
  InternalContentLinkService({InternalContentLinkTransport? transport})
    : _transport = transport ?? MethodChannelInternalContentLinkTransport() {
    _controller = StreamController<InternalContentLink?>.broadcast(
      onListen: _flushBufferedLinks,
    );
  }

  static final instance = InternalContentLinkService();

  final InternalContentLinkTransport _transport;
  late final StreamController<InternalContentLink?> _controller;
  final Queue<InternalContentLink?> _bufferedLinks = Queue();
  bool _started = false;
  bool _draining = false;
  bool _drainRequested = false;

  Stream<InternalContentLink?> get links => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _transport.setPendingLinksListener(_drain);
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining) {
      _drainRequested = true;
      return;
    }
    _draining = true;
    try {
      for (final raw in await _transport.takePendingLinks()) {
        if (raw is! String) continue;
        _publish(InternalContentLink.parse(raw));
      }
    } on MissingPluginException {
      // Other platforms and widget tests simply have no native link bridge.
    } on PlatformException {
      // A transient platform-channel error must not stop normal app startup.
    } finally {
      _draining = false;
      if (_drainRequested) {
        _drainRequested = false;
        unawaited(_drain());
      }
    }
  }

  void _publish(InternalContentLink? link) {
    if (_controller.hasListener) {
      _controller.add(link);
      return;
    }
    if (_bufferedLinks.contains(link)) return;
    if (_bufferedLinks.length >= 16) _bufferedLinks.removeFirst();
    _bufferedLinks.addLast(link);
  }

  void _flushBufferedLinks() {
    while (_controller.hasListener && _bufferedLinks.isNotEmpty) {
      _controller.add(_bufferedLinks.removeFirst());
    }
  }
}
