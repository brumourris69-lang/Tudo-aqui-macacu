import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/local_auth_diagnostics.dart';

void main() {
  test('successful retry records each phase and ends ready', () async {
    final lines = <String>[];

    await runLocalSessionRetryDiagnostics(
      session: LocalAuthSessionCategory.registered,
      enabled: true,
      sink: lines.add,
      pendingAfter: const Duration(seconds: 1),
      validateAuth: () async {},
      validateServices: () async {},
      checkAdminAuthorization: () async {},
    );

    expect(lines.map((line) => RegExp(r'stage=([^;]+)').firstMatch(line)![1]), [
      'retry_started',
      'retry_auth_started',
      'retry_auth_succeeded',
      'retry_services_started',
      'retry_services_succeeded',
      'retry_admin_authorization_started',
      'retry_admin_authorization_completed',
      'retry_succeeded',
      'retry_completed',
    ]);
    expect(lines.last, contains('navigation=ready'));
    expect(lines.every((line) => line.contains('elapsedMs=')), isTrue);
  });

  test('failed retry records sanitized failure and ends in recovery', () async {
    final lines = <String>[];
    final error = FirebaseAuthException(
      code: 'unknown',
      message: 'private@example.invalid secret-token',
      email: 'private@example.invalid',
    );

    await expectLater(
      runLocalSessionRetryDiagnostics(
        session: LocalAuthSessionCategory.registered,
        enabled: true,
        sink: lines.add,
        validateAuth: () async => throw error,
        validateServices: () async {},
        checkAdminAuthorization: () async {},
      ),
      throwsA(same(error)),
    );

    expect(lines.any((line) => line.contains('stage=retry_failed')), isTrue);
    expect(lines.last, contains('stage=retry_completed'));
    expect(lines.last, contains('navigation=recovery'));
    expect(lines.join('\n'), contains('code=unknown'));
    expect(lines.join('\n'), isNot(contains('private@example.invalid')));
    expect(lines.join('\n'), isNot(contains('secret-token')));
  });

  test('pending retry is distinguishable from eventual completion', () async {
    final lines = <String>[];
    final adminCheck = Completer<void>();

    final retry = runLocalSessionRetryDiagnostics(
      session: LocalAuthSessionCategory.registered,
      enabled: true,
      sink: lines.add,
      pendingAfter: const Duration(milliseconds: 1),
      validateAuth: () async {},
      validateServices: () async {},
      checkAdminAuthorization: () => adminCheck.future,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(lines.any((line) => line.contains('stage=retry_pending')), isTrue);
    expect(
      lines.where((line) => line.contains('stage=retry_completed')),
      isEmpty,
    );

    adminCheck.complete();
    await retry;
    expect(
      lines.where((line) => line.contains('stage=retry_completed')),
      hasLength(1),
    );
    expect(lines.last, contains('navigation=ready'));
  });

  test('disabled retry diagnostics emit no log lines', () async {
    final lines = <String>[];

    await runLocalSessionRetryDiagnostics(
      session: LocalAuthSessionCategory.registered,
      enabled: false,
      sink: lines.add,
      validateAuth: () async {},
      validateServices: () async {},
      checkAdminAuthorization: () async {},
    );

    expect(lines, isEmpty);
  });
}
