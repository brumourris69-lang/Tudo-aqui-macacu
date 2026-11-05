import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'apple_sign_in_configuration.dart';
import 'guest_session.dart';
import 'admin_authorization.dart';
import '../config/local_firebase_bootstrap.dart';
import '../config/local_search_environment.dart';
import '../config/staging_environment.dart';
import '../config/beta_environment.dart';
import '../content/secure_backend.dart';
import 'local_auth_diagnostics.dart';

bool isRegisteredUser(User? user) => user != null && !user.isAnonymous;

bool shouldCreateVisitorSession({
  required bool localSearchEnabled,
  required bool stagingEnabled,
  required bool betaEnabled,
  required bool productionAuthorized,
  required bool normalDebugAuthorized,
}) =>
    !betaEnabled &&
    !localSearchEnabled &&
    (stagingEnabled || productionAuthorized || normalDebugAuthorized);

bool shouldValidateRestoredSession({
  required bool localSearchEnabled,
  required bool betaEnabled,
  required bool createVisitorSession,
}) => localSearchEnabled || betaEnabled || createVisitorSession;

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
    if ((StagingEnvironment.enabled || BetaEnvironment.enabled) &&
        LocalSearchEnvironment.enabled) {
      throw StateError('Ambientes de homologação e demo não podem coexistir.');
    }
    if (LocalSearchEnvironment.enabled) {
      LocalSearchEnvironment.requireDemo(
        FirebaseAuth.instance.app.options.projectId,
      );
    }
    if (StagingEnvironment.enabled) StagingEnvironment.requireReady();
    if (BetaEnvironment.enabled) {
      BetaEnvironment.requireFirebaseProject(
        FirebaseAuth.instance.app.options.projectId,
      );
    }
    final createVisitorSession = shouldCreateVisitorSession(
      localSearchEnabled: LocalSearchEnvironment.enabled,
      stagingEnabled: StagingEnvironment.enabled,
      betaEnabled: BetaEnvironment.enabled,
      productionAuthorized: SecureBackend.productionAuthorized,
      normalDebugAuthorized: SecureBackend.normalDebugAuthorized,
    );
    if (!shouldValidateRestoredSession(
      localSearchEnabled: LocalSearchEnvironment.enabled,
      betaEnabled: BetaEnvironment.enabled,
      createVisitorSession: createVisitorSession,
    )) {
      return FirebaseAuth.instance.currentUser;
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
    if (!createVisitorSession) return null;
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

  static Future<UserCredential> signInCredential(AuthCredential credential) {
    _requireBetaProjectWhenEnabled();
    return guestSession.registeredSignIn(
      () => FirebaseAuth.instance.signInWithCredential(credential),
    );
  }

  /// Uses the native Apple provider only for an explicitly configured iOS Beta.
  /// This never links an Apple identity to another account automatically.
  static Future<UserCredential> signInWithApple() =>
      authenticateWithAppleProvider<UserCredential>(
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
        betaBuildEnabled:
            BetaEnvironment.iosBuildEnabled &&
            BetaEnvironment.enabled &&
            !BetaEnvironment.sparkLocal,
        betaReady: BetaEnvironment.ready,
        providerConfigured: BetaEnvironment.iosAppleSignInEnabled,
        authenticate: (provider) => guestSession.registeredSignIn(() async {
          BetaEnvironment.requireFirebaseProject(
            FirebaseAuth.instance.app.options.projectId,
          );
          return FirebaseAuth.instance.signInWithProvider(provider);
        }),
      );

  // The local Emulator Admin form uses email/password; normal login stays Google.
  static Future<UserCredential> signInEmail(String email, String password) {
    _requireBetaProjectWhenEnabled();
    return guestSession.registeredSignIn(
      () => FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  static Future<UserCredential> createEmailAccount(
    String email,
    String password, {
    required String displayName,
  }) {
    _requireBetaProjectWhenEnabled();
    return guestSession.registeredSignIn(() async {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final name = displayName.trim();
      if (name.isNotEmpty) {
        try {
          await credential.user?.updateDisplayName(name);
        } catch (_) {
          // Account creation already succeeded; a profile label is noncritical.
        }
      }
      return credential;
    });
  }

  static Future<void> sendPasswordResetEmail(String email) {
    _requireBetaProjectWhenEnabled();
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  /// Sends verification only for the currently authenticated account. This
  /// deliberately has no Admin SDK equivalent in the client flow.
  static Future<void> sendEmailVerification() async {
    _requireBetaProjectWhenEnabled();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || user.email == null) {
      throw StateError('Entre com sua conta de e-mail para verificá-la.');
    }
    if (!user.emailVerified) await user.sendEmailVerification();
  }

  /// Reloads the signed-in user's Firebase Auth state after they follow the
  /// verification link in their inbox.
  static Future<bool> refreshEmailVerificationStatus() async {
    _requireBetaProjectWhenEnabled();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || user.email == null) return false;
    await user.reload();
    final refreshed = FirebaseAuth.instance.currentUser;
    return refreshed != null &&
        refreshed.uid == user.uid &&
        refreshed.emailVerified;
  }

  static void _requireBetaProjectWhenEnabled() {
    if (BetaEnvironment.enabled) {
      BetaEnvironment.requireFirebaseProject(
        FirebaseAuth.instance.app.options.projectId,
      );
    }
  }

  static Future<User> updateDisplayName(String displayName) =>
      guestSession.registeredSignIn(() async {
        final name = displayName.trim();
        if (name.length < 2 || name.length > 80) {
          throw ArgumentError.value(displayName, 'displayName');
        }
        final current = FirebaseAuth.instance.currentUser;
        if (current == null || current.isAnonymous) {
          throw StateError('Uma conta autenticada é necessária.');
        }
        await current.updateDisplayName(name);
        await current.reload();
        final refreshed = FirebaseAuth.instance.currentUser;
        if (refreshed == null || refreshed.uid != current.uid) {
          throw StateError('A sessão mudou durante a atualização do perfil.');
        }
        return refreshed;
      });

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
  static Future<User?> continueAsLocalVisitor() async {
    if (!LocalSearchEnvironment.enabled) {
      throw StateError('Visitante de recuperação exige searchLocal.');
    }
    LocalSearchEnvironment.requireDemo(
      FirebaseAuth.instance.app.options.projectId,
    );
    await guestSession.registeredSignIn(() => FirebaseAuth.instance.signOut());
    return null;
  }

  static Future<void> logout() async {
    if (StagingEnvironment.enabled) StagingEnvironment.requireReady();
    _requireBetaProjectWhenEnabled();
    await AdminAuthorization.instance.updateUser(null);
    try {
      if (StagingEnvironment.enabled || SecureBackend.productionAuthorized) {
        await guestSession.logout(() => FirebaseAuth.instance.signOut());
      } else {
        await FirebaseAuth.instance.signOut();
      }
    } finally {
      // Keep visible capabilities aligned even if Auth emits its stream later.
      await AdminAuthorization.instance.updateUser(
        FirebaseAuth.instance.currentUser,
      );
    }
  }
}
