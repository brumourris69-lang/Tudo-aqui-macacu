import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

enum LocalAuthSessionCategory { none, anonymous, registered }

enum LocalAuthDiagnosticStage {
  restoreStarted,
  restoreSucceeded,
  restoreFailed,
  idTokenCheckStarted,
  idTokenCheckSucceeded,
  idTokenFailed,
  anonymousRecoveryStarted,
  anonymousSignOutStarted,
  anonymousSignOutSucceeded,
  anonymousSignOutFailed,
  anonymousSignInStarted,
  anonymousSessionCreated,
  anonymousSignInFailed,
  anonymousRecoveryFailed,
  anonymousRecoverySucceeded,
  visitorEnsureStarted,
  visitorEnsureCompleted,
  visitorEnsureFailed,
  retryStarted,
  retryPending,
  retryAuthStarted,
  retryAuthSucceeded,
  retryAuthFailed,
  retryServicesStarted,
  retryServicesSucceeded,
  retryServicesFailed,
  retryAdminAuthorizationStarted,
  retryAdminAuthorizationCompleted,
  retryAdminAuthorizationFailed,
  retrySucceeded,
  retryFailed,
  retryCompleted,
}

enum LocalAuthRetryPhase { auth, services, adminAuthorization }

enum LocalAuthRetryNavigation { recovery, ready }

class LocalAuthDiagnosticEvent {
  LocalAuthDiagnosticEvent({
    required this.stage,
    required this.session,
    this.elapsedMs,
    this.phase,
    this.navigation,
    Object? error,
  }) : exceptionType = error == null
           ? null
           : error is FirebaseAuthException
           ? 'FirebaseAuthException'
           : 'OtherException',
       code = error is FirebaseAuthException ? _safeCode(error.code) : null;

  final LocalAuthDiagnosticStage stage;
  final LocalAuthSessionCategory session;
  final int? elapsedMs;
  final LocalAuthRetryPhase? phase;
  final LocalAuthRetryNavigation? navigation;
  final String? exceptionType;
  final String? code;

  String toLogLine() {
    final fields = <String>[
      'stage=${_stageName(stage)}',
      'session=${session.name}',
      if (elapsedMs != null) 'elapsedMs=$elapsedMs',
      if (phase != null) 'phase=${_phaseName(phase!)}',
      if (navigation != null) 'navigation=${navigation!.name}',
      if (exceptionType != null) 'exceptionType=$exceptionType',
      if (code != null) 'code=$code',
    ];
    return 'Local Auth diagnostic: ${fields.join('; ')}.';
  }

  static String _stageName(LocalAuthDiagnosticStage stage) => switch (stage) {
    LocalAuthDiagnosticStage.restoreStarted => 'restore_started',
    LocalAuthDiagnosticStage.restoreSucceeded => 'restore_succeeded',
    LocalAuthDiagnosticStage.restoreFailed => 'restore_failed',
    LocalAuthDiagnosticStage.idTokenCheckStarted => 'id_token_check_started',
    LocalAuthDiagnosticStage.idTokenCheckSucceeded =>
      'id_token_check_succeeded',
    LocalAuthDiagnosticStage.idTokenFailed => 'id_token_check_failed',
    LocalAuthDiagnosticStage.anonymousRecoveryStarted =>
      'anonymous_recovery_started',
    LocalAuthDiagnosticStage.anonymousSignOutStarted =>
      'anonymous_sign_out_started',
    LocalAuthDiagnosticStage.anonymousSignOutSucceeded =>
      'anonymous_sign_out_succeeded',
    LocalAuthDiagnosticStage.anonymousSignOutFailed =>
      'anonymous_sign_out_failed',
    LocalAuthDiagnosticStage.anonymousSignInStarted =>
      'anonymous_sign_in_started',
    LocalAuthDiagnosticStage.anonymousSessionCreated =>
      'anonymous_session_created',
    LocalAuthDiagnosticStage.anonymousSignInFailed =>
      'anonymous_sign_in_failed',
    LocalAuthDiagnosticStage.anonymousRecoveryFailed =>
      'anonymous_recovery_failed',
    LocalAuthDiagnosticStage.anonymousRecoverySucceeded =>
      'anonymous_recovery_succeeded',
    LocalAuthDiagnosticStage.visitorEnsureStarted => 'visitor_ensure_started',
    LocalAuthDiagnosticStage.visitorEnsureCompleted =>
      'visitor_ensure_completed',
    LocalAuthDiagnosticStage.visitorEnsureFailed => 'visitor_ensure_failed',
    LocalAuthDiagnosticStage.retryStarted => 'retry_started',
    LocalAuthDiagnosticStage.retryPending => 'retry_pending',
    LocalAuthDiagnosticStage.retryAuthStarted => 'retry_auth_started',
    LocalAuthDiagnosticStage.retryAuthSucceeded => 'retry_auth_succeeded',
    LocalAuthDiagnosticStage.retryAuthFailed => 'retry_auth_failed',
    LocalAuthDiagnosticStage.retryServicesStarted => 'retry_services_started',
    LocalAuthDiagnosticStage.retryServicesSucceeded =>
      'retry_services_succeeded',
    LocalAuthDiagnosticStage.retryServicesFailed => 'retry_services_failed',
    LocalAuthDiagnosticStage.retryAdminAuthorizationStarted =>
      'retry_admin_authorization_started',
    LocalAuthDiagnosticStage.retryAdminAuthorizationCompleted =>
      'retry_admin_authorization_completed',
    LocalAuthDiagnosticStage.retryAdminAuthorizationFailed =>
      'retry_admin_authorization_failed',
    LocalAuthDiagnosticStage.retrySucceeded => 'retry_succeeded',
    LocalAuthDiagnosticStage.retryFailed => 'retry_failed',
    LocalAuthDiagnosticStage.retryCompleted => 'retry_completed',
  };

  static String _phaseName(LocalAuthRetryPhase phase) => switch (phase) {
    LocalAuthRetryPhase.auth => 'auth',
    LocalAuthRetryPhase.services => 'services',
    LocalAuthRetryPhase.adminAuthorization => 'admin_authorization',
  };

  static String _safeCode(String code) {
    final normalized = code.toLowerCase();
    return RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(normalized)
        ? normalized
        : 'unavailable';
  }
}

/// Adds local-only, allowlisted diagnostics around the existing retry steps.
/// It never changes timeout, authentication, authorization, or navigation
/// behavior. A pending marker is informational and does not cancel the work.
Future<void> runLocalSessionRetryDiagnostics({
  required LocalAuthSessionCategory session,
  required bool enabled,
  required Future<void> Function() validateAuth,
  required Future<void> Function() validateServices,
  required Future<void> Function() checkAdminAuthorization,
  void Function(String message)? sink,
  Duration pendingAfter = const Duration(seconds: 10),
}) async {
  final total = Stopwatch()..start();
  var navigation = LocalAuthRetryNavigation.recovery;
  LocalAuthRetryPhase? activePhase;

  void record(
    LocalAuthDiagnosticStage stage, {
    LocalAuthRetryPhase? phase,
    Object? error,
    int? elapsedMs,
    LocalAuthRetryNavigation? destination,
  }) {
    emitLocalAuthDiagnostic(
      LocalAuthDiagnosticEvent(
        stage: stage,
        session: session,
        elapsedMs: elapsedMs,
        phase: phase,
        navigation: destination,
        error: error,
      ),
      enabled: enabled,
      sink: sink,
    );
  }

  Future<void> runPhase({
    required LocalAuthRetryPhase phase,
    required LocalAuthDiagnosticStage started,
    required LocalAuthDiagnosticStage succeeded,
    required LocalAuthDiagnosticStage failed,
    required Future<void> Function() action,
  }) async {
    activePhase = phase;
    final timer = Stopwatch()..start();
    record(started, phase: phase, elapsedMs: 0);
    try {
      await action();
      record(succeeded, phase: phase, elapsedMs: timer.elapsedMilliseconds);
    } catch (error) {
      record(
        failed,
        phase: phase,
        elapsedMs: timer.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
  }

  record(
    LocalAuthDiagnosticStage.retryStarted,
    elapsedMs: 0,
    destination: LocalAuthRetryNavigation.recovery,
  );
  Timer? pendingTimer;
  if (enabled) {
    pendingTimer = Timer(pendingAfter, () {
      record(
        LocalAuthDiagnosticStage.retryPending,
        elapsedMs: total.elapsedMilliseconds,
        phase: activePhase,
        destination: LocalAuthRetryNavigation.recovery,
      );
    });
  }

  try {
    await runPhase(
      phase: LocalAuthRetryPhase.auth,
      started: LocalAuthDiagnosticStage.retryAuthStarted,
      succeeded: LocalAuthDiagnosticStage.retryAuthSucceeded,
      failed: LocalAuthDiagnosticStage.retryAuthFailed,
      action: validateAuth,
    );
    await runPhase(
      phase: LocalAuthRetryPhase.services,
      started: LocalAuthDiagnosticStage.retryServicesStarted,
      succeeded: LocalAuthDiagnosticStage.retryServicesSucceeded,
      failed: LocalAuthDiagnosticStage.retryServicesFailed,
      action: validateServices,
    );
    activePhase = LocalAuthRetryPhase.adminAuthorization;
    final adminTimer = Stopwatch()..start();
    record(
      LocalAuthDiagnosticStage.retryAdminAuthorizationStarted,
      phase: LocalAuthRetryPhase.adminAuthorization,
      elapsedMs: 0,
    );
    try {
      await checkAdminAuthorization();
      // This means the authorization refresh/check finished; it deliberately
      // does not report whether any individual permission was granted.
      record(
        LocalAuthDiagnosticStage.retryAdminAuthorizationCompleted,
        elapsedMs: adminTimer.elapsedMilliseconds,
      );
    } catch (error) {
      record(
        LocalAuthDiagnosticStage.retryAdminAuthorizationFailed,
        elapsedMs: adminTimer.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
    navigation = LocalAuthRetryNavigation.ready;
    record(
      LocalAuthDiagnosticStage.retrySucceeded,
      elapsedMs: total.elapsedMilliseconds,
      destination: navigation,
    );
  } catch (error) {
    record(
      LocalAuthDiagnosticStage.retryFailed,
      elapsedMs: total.elapsedMilliseconds,
      error: error,
      destination: LocalAuthRetryNavigation.recovery,
    );
    rethrow;
  } finally {
    pendingTimer?.cancel();
    record(
      LocalAuthDiagnosticStage.retryCompleted,
      elapsedMs: total.elapsedMilliseconds,
      destination: navigation,
    );
  }
}

void emitLocalAuthDiagnostic(
  LocalAuthDiagnosticEvent event, {
  required bool enabled,
  void Function(String message)? sink,
}) {
  if (!enabled) return;
  final line = event.toLogLine();
  if (sink != null) {
    sink(line);
  } else {
    debugPrint(line);
  }
}
