/// Coordinates Auth operations without creating Firestore profiles.
class GuestSession<T> {
  GuestSession({required this.current, required this.anonymousSignIn});
  final T? Function() current;
  final Future<T?> Function() anonymousSignIn;
  Future<T?>? _pending;
  bool _transition = false;
  bool _failed = false;

  Future<T?> ensureVisitor() {
    final existing = current();
    if (existing != null) return Future.value(existing);
    if (_transition || _failed) return Future.value(null);
    return _pending ??= _createVisitor();
  }

  Future<T?> _createVisitor() async {
    try {
      return current() ?? await anonymousSignIn();
    } catch (_) {
      _failed = true; // No repeated sign-ins on widget rebuilds after failure.
      rethrow;
    } finally {
      _pending = null;
    }
  }

  Future<R> registeredSignIn<R>(Future<R> Function() action) async {
    if (_transition) throw StateError('Autenticação em andamento.');
    _transition = true;
    try {
      try {
        await _pending;
      } catch (_) {
        /* Registered login can still work. */
      }
      return await action();
    } finally {
      _transition = false;
    }
  }

  Future<void> logout(Future<void> Function() action) async {
    await registeredSignIn(action);
    _failed = false;
    await ensureVisitor();
  }
}
