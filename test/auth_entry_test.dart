import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/auth_error_message.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/features/auth/local_demo_login.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/auth/email_password_auth.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets(
    'login offers email access without requiring an account to browse',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const GoogleLoginView()),
      );

      if (localDemoLoginEnabled) {
        expect(find.byKey(const Key('local-demo-email')), findsOneWidget);
        expect(find.byKey(const Key('local-demo-password')), findsOneWidget);
        expect(find.text('Continuar com Google'), findsNothing);
        return;
      }

      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('Entrar com e-mail'), findsOneWidget);
      expect(find.textContaining('Criar conta é opcional'), findsOneWidget);

      await tester.tap(find.text('Entrar com e-mail'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailPasswordAuthView), findsOneWidget);
    },
  );

  testWidgets('email access remains reachable in a compact Android window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const GoogleLoginView()),
    );
    final layoutException = tester.takeException();
    expect(layoutException, isNull, reason: layoutException?.toString());
    if (localDemoLoginEnabled) {
      expect(find.byKey(const Key('local-demo-email')), findsOneWidget);
      expect(find.byKey(const Key('local-demo-password')), findsOneWidget);
      expect(find.byKey(const Key('open-email-auth')), findsNothing);
      return;
    }
    final emailButton = find.byKey(const Key('open-email-auth'));
    expect(emailButton, findsOneWidget);
    await tester.ensureVisible(emailButton);
    await tester.tap(emailButton);
    await tester.pumpAndSettle();
    expect(find.byType(EmailPasswordAuthView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email sign-in validates fields and reports safe auth errors', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EmailPasswordAuthView(
          signIn: (_, _) async {
            attempts++;
            throw FirebaseAuthException(code: 'invalid-credential');
          },
          register: (_, _, _) async {},
          resetPassword: (_) async {},
          onAuthenticated: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('email-auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(attempts, 0);

    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'user@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'bad-password',
    );
    await tester.tap(find.byKey(const Key('email-auth-submit')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(
      find.text(
        'E-mail ou senha incorretos. Confira os dados e tente novamente.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('email-auth-error')),
        matching: find.text('bad-password'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'Google cancellation is handled locally without forcing account access',
    (tester) async {
      var chooserCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: GoogleLoginView(
            googleAccountChooserForTesting: () async {
              chooserCalls++;
              return null;
            },
          ),
        ),
      );

      if (localDemoLoginEnabled) {
        expect(chooserCalls, 0);
        expect(find.byKey(const Key('local-demo-email')), findsOneWidget);
        expect(find.text('Continuar com Google'), findsNothing);
        return;
      }

      await tester.tap(find.text('Continuar com Google'));
      await tester.pumpAndSettle();

      if (BetaEnvironment.enabled) {
        expect(chooserCalls, 0);
        expect(
          find.text(
            'Não foi possível entrar com o Google. Verifique sua conexão e tente novamente.',
          ),
          findsOneWidget,
        );
        expect(find.text('Continuar sem conta'), findsOneWidget);
        return;
      }

      expect(chooserCalls, 1);
      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('Continuar sem conta'), findsOneWidget);
      expect(find.byKey(const Key('email-auth-error')), findsNothing);
    },
  );

  testWidgets('registration sends trimmed name and email once', (tester) async {
    String? receivedName;
    String? receivedEmail;
    String? receivedPassword;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EmailPasswordAuthView(
          signIn: (_, _) async {},
          register: (name, email, password) async {
            receivedName = name;
            receivedEmail = email;
            receivedPassword = password;
          },
          resetPassword: (_) async {},
          onAuthenticated: () async => completed = true,
        ),
      ),
    );

    final registrationToggle = find.byKey(const Key('email-auth-mode'));
    await tester.ensureVisible(registrationToggle);
    await tester.tap(registrationToggle);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('auth-name')), '  Ana Lima  ');
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      ' ana@example.invalid ',
    );
    await tester.enterText(find.byKey(const Key('auth-password')), 'short');
    await tester.tap(find.byKey(const Key('email-auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Use pelo menos 6 caracteres.'), findsOneWidget);
    expect(receivedEmail, isNull);

    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'strong-test-password',
    );
    await tester.tap(find.byKey(const Key('email-auth-submit')));
    await tester.pumpAndSettle();

    expect(receivedName, 'Ana Lima');
    expect(receivedEmail, 'ana@example.invalid');
    expect(receivedPassword, 'strong-test-password');
    expect(completed, isTrue);
  });

  testWidgets('Beta email login waits for verification before entering app', (
    tester,
  ) async {
    var completed = false;
    var verified = false;
    var verificationRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EmailPasswordAuthView(
          signIn: (_, _) async {},
          register: (_, _, _) async {},
          resetPassword: (_) async {},
          requireEmailVerification: true,
          sendEmailVerification: () async => verificationRequests++,
          refreshEmailVerification: () async => verified,
          onAuthenticated: () async => completed = true,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'admin@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'safe-test-password',
    );
    await tester.tap(find.byKey(const Key('email-auth-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Confirme seu e-mail'), findsOneWidget);
    expect(completed, isFalse);
    await tester.tap(find.byKey(const Key('send-email-verification')));
    await tester.pumpAndSettle();
    expect(verificationRequests, 1);
    expect(find.byKey(const Key('email-verification-sent')), findsOneWidget);

    verified = true;
    await tester.tap(find.byKey(const Key('refresh-email-verification')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('unverified account cannot bypass verification by refreshing', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EmailPasswordAuthView(
          signIn: (_, _) async {},
          register: (_, _, _) async {},
          resetPassword: (_) async {},
          requireEmailVerification: true,
          sendEmailVerification: () async {},
          refreshEmailVerification: () async => false,
          onAuthenticated: () async => completed = true,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'admin@example.invalid',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'safe-test-password',
    );
    await tester.tap(find.byKey(const Key('email-auth-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refresh-email-verification')));
    await tester.pumpAndSettle();

    expect(completed, isFalse);
    expect(
      find.text(
        'Ainda não confirmamos o e-mail. Abra o link recebido e tente novamente.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'email sign-in exposes loading and rejects duplicate submissions',
    (tester) async {
      final pending = Completer<void>();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EmailPasswordAuthView(
            signIn: (_, _) {
              attempts++;
              return pending.future;
            },
            register: (_, _, _) async {},
            resetPassword: (_) async {},
            onAuthenticated: () async {},
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'ana@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('auth-password')),
        'correct-test-password',
      );
      await tester.tap(find.byKey(const Key('email-auth-submit')));
      await tester.pump();

      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('email-auth-submit')),
      );
      expect(submit.onPressed, isNull);
      expect(find.text('Aguarde…'), findsOneWidget);
      expect(attempts, 1);

      pending.complete();
      await tester.pumpAndSettle();
      expect(attempts, 1);
    },
  );

  testWidgets(
    'password reset uses email and confirms without revealing account state',
    (tester) async {
      String? resetEmail;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: EmailPasswordAuthView(
            signIn: (_, _) async {},
            register: (_, _, _) async {},
            resetPassword: (email) async => resetEmail = email,
            onAuthenticated: () async {},
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('auth-email')),
        'ana@example.invalid',
      );
      await tester.tap(find.byKey(const Key('auth-reset-password')));
      await tester.pumpAndSettle();

      expect(resetEmail, 'ana@example.invalid');
      expect(
        find.text(
          'Se existir uma conta para esse e-mail, você receberá instruções para redefinir a senha.',
        ),
        findsOneWidget,
      );
    },
  );

  test('auth errors are mapped to safe, non-sensitive messages', () {
    expect(
      authErrorMessage(
        FirebaseAuthException(code: 'network-request-failed'),
        action: AuthErrorAction.signIn,
      ),
      'Sem conexão no momento. Verifique a internet e tente novamente.',
    );
    expect(
      authErrorMessage(
        StateError('secret'),
        action: AuthErrorAction.createAccount,
      ),
      'Não foi possível concluir agora. Tente novamente em instantes.',
    );
  });
}
