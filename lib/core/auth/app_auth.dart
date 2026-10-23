import 'package:firebase_auth/firebase_auth.dart';
import 'guest_session.dart';
import '../config/local_firebase_bootstrap.dart';
import '../config/local_search_environment.dart';
import '../config/staging_environment.dart';
import '../content/secure_backend.dart';
import 'local_auth_diagnostics.dart';

bool isRegisteredUser(User? user) => user != null && !user.isAnonymous;

LocalAuthSessionCategory _localSessionCategory(User? user) => user == null
    ? LocalAuthSessionCategory.none
    : user.isAnonymous
    ? LocalAuthSessionCategory.anonymous
    : LocalAuthSessionCategory.registered;

void _recordLocalAuthDiagnostic(
  LocalAuthDiagnosticStage stage, {
  required LocalAuthSessionCategory session,
  int? elapsedMs,
  Object? error,
}) {
  emitLocalAuthDiagnostic(
    LocalAuthDiagnosticEvent(
      stage: stage,
      session: session,
      elapsedMs: elapsedMs,
      error: error,
    ),
    enabled: LocalSearchEnvironment.enabled,
  );
}

class AppAuth {
  AppAuth._();
  static final guestSession = GuestSession<User>(
    current: () => FirebaseAuth.instance.currentUser,
    anonymousSignIn: _signInLocalVisitor,
  );

  static Future<User?> _signInLocalVisitor() async {
    final timer = Stopwatch()..start();
    _recordLocalAuthDiagnostic(
      LocalAuthDiagnosticStage.anonymousSignInStarted,
      session: LocalAuthSessionCategory.none,
    );
    try {
      final user = (await FirebaseAuth.instance.signInAnonymously()).user;
      timer.stop();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.anonymousSessionCreated,
        session: _localSessionCategory(user),
        elapsedMs: timer.elapsedMilliseconds,
      );
      return user;
    } catch (error) {
      timer.stop();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.anonymousSignInFailed,
        session: LocalAuthSessionCategory.none,
        elapsedMs: timer.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
  }

  static Future<User?> ensureVisitor() async {
    if (StagingEnvironment.enabled && LocalSearchEnvironment.enabled) {
      throw StateError('Ambientes de homologação e demo não podem coexistir.');
    }
    if (StagingEnvironment.enabled) StagingEnvironment.requireReady();
    if (!LocalSearchEnvironment.enabled &&
        !StagingEnvironment.enabled &&
        !SecureBackend.productionAuthorized &&
        !SecureBackend.normalDebugAuthorized) {
      return FirebaseAuth.instance.currentUser;
    }
    if (LocalSearchEnvironment.enabled) {
      LocalSearchEnvironment.requireDemo(
        FirebaseAuth.instance.app.options.projectId,
      );
    }
    // Let the SDK restore a persisted account before deciding to create a guest.
    User? restored;
    final restoreTimer = Stopwatch()..start();
    _recordLocalAuthDiagnostic(
      LocalAuthDiagnosticStage.restoreStarted,
      session: LocalAuthSessionCategory.none,
    );
    try {
      restored = await FirebaseAuth.instance.authStateChanges().first;
      restoreTimer.stop();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.restoreSucceeded,
        session: _localSessionCategory(restored),
        elapsedMs: restoreTimer.elapsedMilliseconds,
      );
    } catch (error) {
      restoreTimer.stop();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.restoreFailed,
        session: _localSessionCategory(FirebaseAuth.instance.currentUser),
        elapsedMs: restoreTimer.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
    if (restored != null) {
      final tokenCheckTimer = Stopwatch()..start();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.idTokenCheckStarted,
        session: _localSessionCategory(restored),
      );
      try {
        // Validate a restored emulator session before any Firestore read.
        await restored.getIdToken();
        tokenCheckTimer.stop();
        _recordLocalAuthDiagnostic(
          LocalAuthDiagnosticStage.idTokenCheckSucceeded,
          session: _localSessionCategory(restored),
          elapsedMs: tokenCheckTimer.elapsedMilliseconds,
        );
      } catch (error) {
        tokenCheckTimer.stop();
        _recordLocalAuthDiagnostic(
          LocalAuthDiagnosticStage.idTokenFailed,
          session: _localSessionCategory(restored),
          elapsedMs: tokenCheckTimer.elapsedMilliseconds,
          error: error,
        );
        // searchLocal leaves every restored session untouched and offers
        // explicit recovery. Keep the pre-existing non-local behavior isolated
        // from this demo-only flow.
        if (error is FirebaseAuthException &&
            shouldAutomaticallyRenewAnonymousSession(
              searchLocalEnabled: LocalSearchEnvironment.enabled,
              code: error.code,
              isAnonymous: restored.isAnonymous,
            )) {
          try {
            final renewed = await renewExpiredLocalVisitor<User>(
              wasAnonymous: restored.isAnonymous,
              signOut: () => FirebaseAuth.instance.signOut(),
              signInAnonymously: _signInLocalVisitor,
            );
            return renewed;
          } catch (_) {
            rethrow;
          }
        }
        rethrow;
      }
      return restored;
    }
    final visitorTimer = Stopwatch()..start();
    _recordLocalAuthDiagnostic(
      LocalAuthDiagnosticStage.visitorEnsureStarted,
      session: LocalAuthSessionCategory.none,
    );
    try {
      final visitor = await guestSession.ensureVisitor();
      if (LocalSearchEnvironment.enabled && visitor != null) {
        await visitor.getIdToken();
      }
      visitorTimer.stop();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.visitorEnsureCompleted,
        session: _localSessionCategory(visitor),
        elapsedMs: visitorTimer.elapsedMilliseconds,
      );
      return visitor;
    } catch (error) {
      visitorTimer.stop();
      _recordLocalAuthDiagnostic(
        LocalAuthDiagnosticStage.visitorEnsureFailed,
        session: LocalAuthSessionCategory.none,
        elapsedMs: visitorTimer.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
  }

  static Future<UserCredential> signInCredential(AuthCredential credential) =>
      guestSession.registeredSignIn(
        () => FirebaseAuth.instance.signInWithCredential(credential),
      );

  // The local Emulator Admin form uses email/password; normal login stays Google.
  static Future<UserCredential> signInEmail(String email, String password) =>
      guestSession.registeredSignIn(
        () => FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        ),
      );

  /// Validates the current local account without creating or replacing one.
  static Future<User> validateCurrentLocalSession() async {
    if (!LocalSearchEnvironment.enabled) {
      throw StateError('A validação de sessão é exclusiva do searchLocal.');
    }
    LocalSearchEnvironment.requireDemo(
      FirebaseAuth.instance.app.options.projectId,
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const LocalSearchSessionExpired();
    await user.getIdToken();
    return user;
  }

  /// Starts a visitor session only after the local recovery UI gets consent.
  static Future<User> continueAsLocalVisitor() async {
    if (!LocalSearchEnvironment.enabled) {
      throw StateError('Visitante de recuperação exige searchLocal.');
    }
    LocalSearchEnvironment.requireDemo(
      FirebaseAuth.instance.app.options.projectId,
    );
    final user = await guestSession.replaceWithVisitor(
      () => FirebaseAuth.instance.signOut(),
    );
    if (user == null) throw const LocalSearchSessionExpired();
    return user;
  }

  static Future<void> logout() async {
    if (StagingEnvironment.enabled) StagingEnvironment.requireReady();
    if (LocalSearchEnvironment.enabled ||
        StagingEnvironment.enabled ||
        SecureBackend.productionAuthorized) {
      await guestSession.logout(() => FirebaseAuth.instance.signOut());
    } else {
      await FirebaseAuth.instance.signOut();
    }
  }
}
