import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/auth/local_demo_login.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';

void main() {
  testWidgets('email/password local login is hidden outside searchLocal', (
    tester,
  ) async {
    if (LocalSearchEnvironment.enabled) return;

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LocalDemoLoginForm())),
    );

    expect(find.byKey(const Key('local-demo-email')), findsNothing);
    expect(find.text('Entrar no Emulator local'), findsNothing);
  });

  testWidgets(
    'searchLocal login calls the injected authenticator and reports success',
    (tester) async {
      if (!LocalSearchEnvironment.enabled) return;

      String? receivedEmail;
      String? receivedPassword;
      var succeeded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDemoLoginForm(
              authenticate: (email, password) async {
                receivedEmail = email;
                receivedPassword = password;
              },
              onAuthenticated: () async {
                succeeded = true;
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('local-demo-email')),
        'owner@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('local-demo-password')),
        'fictional-password',
      );
      await tester.tap(find.text('Entrar no Emulator local'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(receivedEmail, 'owner@example.invalid');
      expect(receivedPassword, 'fictional-password');
      expect(succeeded, isTrue);
      expect(
        find.text('Não foi possível entrar. Confira o e-mail e a senha.'),
        findsNothing,
      );
    },
    skip: !LocalSearchEnvironment.enabled,
  );

  testWidgets(
    'searchLocal login displays a safe error without credential data',
    (tester) async {
      if (!LocalSearchEnvironment.enabled) return;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDemoLoginForm(
              authenticate: (_, _) async =>
                  throw StateError('sensitive detail'),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('local-demo-email')),
        'owner@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('local-demo-password')),
        'fictional-password',
      );
      await tester.tap(find.text('Entrar no Emulator local'));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível entrar. Confira o e-mail e a senha.'),
        findsOneWidget,
      );
      expect(find.textContaining('sensitive detail'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.contains('fictional-password') ?? false),
        ),
        findsNothing,
      );
      final passwordEditor = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('local-demo-password')),
          matching: find.byType(EditableText),
        ),
      );
      expect(passwordEditor.obscureText, isTrue);
    },
    skip: !LocalSearchEnvironment.enabled,
  );
}
