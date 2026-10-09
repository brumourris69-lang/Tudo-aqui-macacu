import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/guest_session.dart';
import 'package:tudo_aqui_macacu/core/auth/app_auth.dart';
import 'package:tudo_aqui_macacu/core/auth/app_check_setup.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

class TestUser implements User {
  TestUser(this.isAnonymous, {this.email});
  @override
  final bool isAnonymous;
  @override
  final String? email;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'visitor creates one session and reuses persisted/current session',
    () async {
      String? current;
      var calls = 0;
      final completion = Completer<String>();
      final session = GuestSession<String>(
        current: () => current,
        anonymousSignIn: () async {
          calls++;
          return current = await completion.future;
        },
      );
      final first = session.ensureVisitor();
      final second = session.ensureVisitor();
      completion.complete('anonymous-uid');
      expect(await first, 'anonymous-uid');
      expect(await second, 'anonymous-uid');
      expect(await session.ensureVisitor(), 'anonymous-uid');
      expect(calls, 1);
      // New controller models an app restart after the Auth SDK restores the UID.
      final restored = GuestSession<String>(
        current: () => current,
        anonymousSignIn: () async {
          calls++;
          return 'unexpected';
        },
      );
      expect(await restored.ensureVisitor(), 'anonymous-uid');
      expect(calls, 1);
    },
  );
  test(
    'Google/email existing account is never replaced by anonymous sign-in',
    () async {
      for (final provider in ['google', 'email']) {
        final session = GuestSession<String>(
          current: () => '$provider-uid',
          anonymousSignIn: () async => throw StateError('must not run'),
        );
        expect(await session.ensureVisitor(), '$provider-uid');
      }
    },
  );
  test(
    'registered login waits for anonymous operation and wins the race',
    () async {
      String? current;
      final completion = Completer<String>();
      final session = GuestSession<String>(
        current: () => current,
        anonymousSignIn: () async => current = await completion.future,
      );
      final visitor = session.ensureVisitor();
      final login = session.registeredSignIn(
        () async => current = 'registered-uid',
      );
      expect(await session.ensureVisitor(), isNull);
      completion.complete('guest-uid');
      await visitor;
      await login;
      expect(current, 'registered-uid');
      expect(await session.ensureVisitor(), 'registered-uid');
    },
  );
  test(
    'logout returns to visitor; in-flight transition cannot create another guest',
    () async {
      String? current = 'registered-uid';
      var calls = 0;
      late GuestSession<String> session;
      session = GuestSession<String>(
        current: () => current,
        anonymousSignIn: () async => current = 'guest-${++calls}',
      );
      await session.logout(() async {
        current = null;
        expect(await session.ensureVisitor(), isNull);
      });
      expect(current, 'guest-1');
      expect(calls, 1);
    },
  );
  test(
    'anonymous failure does not loop on rebuild; registered login still works',
    () async {
      String? current;
      var calls = 0;
      final session = GuestSession<String>(
        current: () => current,
        anonymousSignIn: () async {
          calls++;
          throw StateError('unavailable');
        },
      );
      await expectLater(session.ensureVisitor(), throwsStateError);
      expect(await session.ensureVisitor(), isNull);
      expect(calls, 1);
      await session.registeredSignIn(() async => current = 'registered');
      expect(await session.ensureVisitor(), 'registered');
    },
  );
  test(
    'anonymous users cannot become registered/admin through an email field',
    () {
      final anonymous = TestUser(true, email: 'legacy-admin@example.com');
      expect(isRegisteredUser(anonymous), isFalse);
      expect(isAdminUser(anonymous), isFalse);
      expect(isRegisteredUser(null), isFalse);
      expect(isRegisteredUser(TestUser(false)), isTrue);
      expect(
        isAdminUser(TestUser(false, email: 'legacy-admin@example.com')),
        isFalse,
      );
    },
  );
  testWidgets(
    'anonymous Profile retains the visitor interface and login action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ProfileView(count: 0, user: TestUser(true))),
      );
      expect(find.text('Entre para personalizar'), findsOneWidget);
      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('Administração'), findsNothing);
      expect(find.text('Sair da conta'), findsNothing);
    },
  );
  test('App Check policy selects disabled/emulator/debug/native providers', () {
    expect(
      appCheckMode(enabled: false, emulator: false, debug: false),
      AppCheckMode.disabled,
    );
    expect(
      appCheckMode(enabled: true, emulator: true, debug: true),
      AppCheckMode.emulator,
    );
    expect(
      appCheckMode(enabled: true, emulator: false, debug: true),
      AppCheckMode.debugProvider,
    );
    expect(
      appCheckMode(enabled: true, emulator: false, debug: false),
      AppCheckMode.attestation,
    );
  });
  test('production/default boot keeps local auth and App Check disabled', () {
    expect(LocalSearchEnvironment.enabled, isFalse);
    expect(AppCheckSetup.enabled, isFalse);
    expect(
      () => LocalSearchEnvironment.requireDemo('real-project'),
      throwsStateError,
    );
  });
}
