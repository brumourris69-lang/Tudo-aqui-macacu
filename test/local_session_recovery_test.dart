@Tags(['search-local'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/auth/local_session_recovery.dart';

void main() {
  test(
    'unknown Auth errors remain inconclusive, explicit token errors do not',
    () {
      expect(
        classifyLocalSessionFailureCode('INVALID_REFRESH_TOKEN'),
        LocalSessionFailureKind.credentialInvalid,
      );
      expect(
        classifyLocalSessionFailureCode('user-token-expired'),
        LocalSessionFailureKind.credentialInvalid,
      );
      expect(
        classifyLocalSessionFailureCode('unknown'),
        LocalSessionFailureKind.inconclusive,
      );
      expect(
        classifyLocalSessionFailureCode('network-request-failed'),
        LocalSessionFailureKind.inconclusive,
      );
    },
  );

  testWidgets(
    'retry runs only after tap and concurrent taps share one attempt',
    (tester) async {
      final attempt = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionRecoveryView(
            failureKind: LocalSessionFailureKind.inconclusive,
            onValidateCurrentSession: () {
              calls++;
              return attempt.future;
            },
            onSwitchAccount: (_, _) async {},
            onContinueAsVisitor: () async {},
            onReady: (_) => const Text('Área protegida'),
          ),
        ),
      );

      expect(calls, 0);
      expect(find.text('Área protegida'), findsNothing);
      await tester.tap(find.byKey(const Key('retry-session')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('retry-session')));
      await tester.pump();
      expect(calls, 1);

      attempt.complete();
      await tester.pumpAndSettle();
      expect(find.text('Área protegida'), findsOneWidget);
    },
  );

  testWidgets('failed retry keeps protected content inaccessible', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionRecoveryView(
          failureKind: LocalSessionFailureKind.inconclusive,
          onValidateCurrentSession: () async {
            attempts++;
            throw StateError('private diagnostic detail');
          },
          onSwitchAccount: (_, _) async {},
          onContinueAsVisitor: () async {},
          onReady: (_) => const Text('Área protegida'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('retry-session')));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Área protegida'), findsNothing);
    expect(find.textContaining('private diagnostic detail'), findsNothing);
    expect(find.text('Sessão não validada'), findsOneWidget);
  });

  testWidgets(
    'account switch requires confirmation and cancel preserves session',
    (tester) async {
      var signInCalls = 0;
      var visitorCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionRecoveryView(
            failureKind: LocalSessionFailureKind.credentialInvalid,
            onValidateCurrentSession: () async {},
            onSwitchAccount: (_, _) async => signInCalls++,
            onContinueAsVisitor: () async => visitorCalls++,
            onReady: (_) => const Text('Área protegida'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('switch-account')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-demo-email')), findsNothing);
      expect(signInCalls, 0);
      await tester.tap(find.byKey(const Key('cancel-session-change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-demo-email')), findsNothing);
      expect(signInCalls, 0);
      expect(visitorCalls, 0);
      expect(find.text('Área protegida'), findsNothing);
    },
  );

  testWidgets(
    'confirmed account switch shows local login without signing out',
    (tester) async {
      var signInCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionRecoveryView(
            failureKind: LocalSessionFailureKind.inconclusive,
            onValidateCurrentSession: () async {},
            onSwitchAccount: (_, _) async => signInCalls++,
            onContinueAsVisitor: () async {},
            onReady: (_) => const Text('Área protegida'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('switch-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-session-change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-demo-email')), findsOneWidget);
      expect(signInCalls, 0);
      expect(find.text('Área protegida'), findsNothing);
    },
  );

  testWidgets(
    'confirmed account switch authenticates then validates before ready',
    (tester) async {
      var signedIn = false;
      var validated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionRecoveryView(
            failureKind: LocalSessionFailureKind.inconclusive,
            onSwitchAccount: (_, _) async => signedIn = true,
            onContinueAsVisitor: () async {},
            onValidateCurrentSession: () async {
              expect(signedIn, isTrue);
              validated = true;
            },
            onReady: (_) => const Text('Área protegida'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('switch-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-session-change')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('local-demo-email')),
        'a@b.test',
      );
      await tester.enterText(
        find.byKey(const Key('local-demo-password')),
        'secret',
      );
      await tester.tap(find.text('Entrar no Emulator local'));
      await tester.pumpAndSettle();

      expect(signedIn, isTrue);
      expect(validated, isTrue);
      expect(find.text('Área protegida'), findsOneWidget);
    },
  );

  testWidgets('visitor choice mutates the session only after confirmation', (
    tester,
  ) async {
    var visitorCalls = 0;
    final order = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionRecoveryView(
          failureKind: LocalSessionFailureKind.inconclusive,
          onValidateCurrentSession: () async => order.add('validated'),
          onSwitchAccount: (_, _) async {},
          onContinueAsVisitor: () async {
            visitorCalls++;
            order.add('visitor-created');
          },
          onReady: (_) => const Text('Área protegida'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('continue-visitor')));
    await tester.pumpAndSettle();
    expect(visitorCalls, 0);
    await tester.tap(find.byKey(const Key('cancel-session-change')));
    await tester.pumpAndSettle();
    expect(visitorCalls, 0);
    await tester.tap(find.byKey(const Key('continue-visitor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-session-change')));
    await tester.pumpAndSettle();
    expect(visitorCalls, 1);
    expect(order, ['visitor-created', 'validated']);
    expect(find.text('Área protegida'), findsOneWidget);
  });
}
