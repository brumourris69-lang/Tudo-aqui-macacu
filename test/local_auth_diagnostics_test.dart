import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/local_auth_diagnostics.dart';

void main() {
  test('diagnostic output contains only approved fields', () {
    final error = FirebaseAuthException(
      code: 'unknown',
      message: 'private-message@example.invalid refresh-token-secret',
      email: 'private-message@example.invalid',
    );

    final event = LocalAuthDiagnosticEvent(
      stage: LocalAuthDiagnosticStage.idTokenFailed,
      session: LocalAuthSessionCategory.registered,
      elapsedMs: 128,
      error: error,
    );

    expect(
      event.toLogLine(),
      'Local Auth diagnostic: stage=id_token_check_failed; '
      'session=registered; elapsedMs=128; '
      'exceptionType=FirebaseAuthException; code=unknown.',
    );
    expect(event.toLogLine(), isNot(contains('private-message')));
    expect(event.toLogLine(), isNot(contains('refresh-token-secret')));
  });

  test('unsafe exception codes are replaced rather than interpolated', () {
    final event = LocalAuthDiagnosticEvent(
      stage: LocalAuthDiagnosticStage.idTokenFailed,
      session: LocalAuthSessionCategory.anonymous,
      error: FirebaseAuthException(
        code: 'private@example.invalid?token=secret',
        message: 'sensitive text',
      ),
    );

    expect(event.toLogLine(), contains('exceptionType=FirebaseAuthException'));
    expect(event.toLogLine(), contains('code=unavailable.'));
    expect(event.toLogLine(), isNot(contains('private@example.invalid')));
    expect(event.toLogLine(), isNot(contains('secret')));
    expect(event.toLogLine(), isNot(contains('sensitive text')));
  });

  test('normal mode does not emit local auth diagnostics', () {
    final messages = <String>[];

    emitLocalAuthDiagnostic(
      LocalAuthDiagnosticEvent(
        stage: LocalAuthDiagnosticStage.restoreStarted,
        session: LocalAuthSessionCategory.none,
      ),
      enabled: false,
      sink: messages.add,
    );

    expect(messages, isEmpty);
  });

  test(
    'recovery attempt and anonymous session creation are distinct events',
    () {
      final recovery = LocalAuthDiagnosticEvent(
        stage: LocalAuthDiagnosticStage.anonymousRecoveryStarted,
        session: LocalAuthSessionCategory.anonymous,
        error: FirebaseAuthException(code: 'unknown'),
      );
      final created = LocalAuthDiagnosticEvent(
        stage: LocalAuthDiagnosticStage.anonymousSessionCreated,
        session: LocalAuthSessionCategory.anonymous,
        elapsedMs: 21,
      );

      expect(
        recovery.toLogLine(),
        contains('stage=anonymous_recovery_started'),
      );
      expect(recovery.toLogLine(), contains('code=unknown'));
      expect(created.toLogLine(), contains('stage=anonymous_session_created'));
      expect(created.toLogLine(), contains('session=anonymous'));
      expect(recovery.toLogLine(), isNot(contains('created')));
    },
  );

  test('non-auth exceptions expose only a generic type category', () {
    final event = LocalAuthDiagnosticEvent(
      stage: LocalAuthDiagnosticStage.anonymousRecoveryFailed,
      session: LocalAuthSessionCategory.anonymous,
      elapsedMs: 12,
      error: StateError('contains a private address@example.invalid'),
    );

    expect(
      event.toLogLine(),
      'Local Auth diagnostic: stage=anonymous_recovery_failed; '
      'session=anonymous; elapsedMs=12; exceptionType=OtherException.',
    );
    expect(event.toLogLine(), isNot(contains('address@example.invalid')));
  });
}
