import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/auth/local_demo_login.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

class ProfileTestProvider implements UserInfo {
  ProfileTestProvider(this.providerId);

  @override
  final String providerId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfileTestUser implements User {
  ProfileTestUser({
    this.uid = 'profile-test-user',
    this.isAnonymous = false,
    this.email = 'ana@example.invalid',
    this.displayName = 'Ana Lima',
    this.photoURL,
    this.providerData = const [],
  });

  @override
  final String uid;
  @override
  final bool isAnonymous;
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final String? photoURL;
  @override
  final List<UserInfo> providerData;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'account profile shows only available user details and settings',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileView(
            count: 1,
            user: ProfileTestUser(
              providerData: [ProfileTestProvider('password')],
            ),
            privacyPolicyUrl: 'https://example.invalid/privacy',
          ),
        ),
      );

      expect(find.text('Minha Conta'), findsOneWidget);
      expect(find.text('Ana Lima'), findsOneWidget);
      expect(find.text('ana@example.invalid'), findsOneWidget);
      expect(find.byKey(const Key('profile-edit-name')), findsOneWidget);
      expect(find.text('Redefinir senha'), findsOneWidget);
      expect(find.text('Política de privacidade'), findsOneWidget);
      expect(find.text('Administração'), findsNothing);
    },
  );

  testWidgets('account exposes the personal agenda and its saved count', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileView(
          count: 2,
          agendaCount: 3,
          user: ProfileTestUser(),
          onAgenda: () => opened = true,
        ),
      ),
    );

    expect(find.text('Minha Agenda'), findsOneWidget);
    expect(find.text('3 evento(s) salvo(s) na sua conta'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-my-agenda')));
    expect(opened, isTrue);
  });

  testWidgets('account opens notification preferences from the menu', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileView(
          count: 0,
          user: ProfileTestUser(),
          onNotifications: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('profile-notifications')));
    expect(opened, isTrue);
  });

  testWidgets(
    'editing the display name validates and saves the normalized name',
    (tester) async {
      String? savedName;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileView(
            count: 0,
            user: ProfileTestUser(
              providerData: [ProfileTestProvider('google.com')],
            ),
            onUpdateDisplayName: (name) async => savedName = name,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('profile-edit-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name-input')),
        '  Ana Macacu  ',
      );
      await tester.tap(find.byKey(const Key('profile-name-save')));
      await tester.pumpAndSettle();

      expect(savedName, 'Ana Macacu');
      expect(find.text('Ana Macacu'), findsOneWidget);
      expect(find.text('Nome atualizado.'), findsOneWidget);
    },
  );

  testWidgets(
    'password recovery is available only for password-linked accounts',
    (tester) async {
      String? resetEmail;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileView(
            count: 0,
            user: ProfileTestUser(
              providerData: [ProfileTestProvider('password')],
            ),
            onPasswordReset: (email) async => resetEmail = email,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('profile-reset-password')));
      await tester.pumpAndSettle();
      expect(resetEmail, 'ana@example.invalid');
      expect(find.textContaining('Se existir uma conta'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileView(
            count: 0,
            user: ProfileTestUser(
              providerData: [ProfileTestProvider('google.com')],
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('profile-reset-password')), findsNothing);
      expect(find.text('Sua senha é gerenciada pelo Google.'), findsOneWidget);
    },
  );

  testWidgets(
    'logout requires confirmation and reports successful session exit',
    (tester) async {
      var logoutCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileView(
            count: 0,
            user: ProfileTestUser(
              providerData: [ProfileTestProvider('password')],
            ),
            onSignOut: () async => logoutCalls++,
          ),
        ),
      );

      await tester.ensureVisible(find.byKey(const Key('profile-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await tester.pumpAndSettle();
      expect(logoutCalls, 0);
      await tester.tap(find.byKey(const Key('profile-confirm-sign-out')));
      await tester.pumpAndSettle();

      expect(logoutCalls, 1);
      expect(find.text('Você saiu da sua conta.'), findsOneWidget);
    },
  );

  testWidgets(
    'visitor account view keeps public browsing and hides account data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfileView(
            count: 0,
            user: ProfileTestUser(
              isAnonymous: true,
              email: null,
              displayName: null,
              providerData: const [],
            ),
          ),
        ),
      );

      expect(find.text('Entre para personalizar'), findsOneWidget);
      if (localDemoLoginEnabled) {
        expect(find.text('Entrar com conta demo'), findsOneWidget);
      } else {
        expect(find.text('Continuar com Google'), findsOneWidget);
      }
      expect(find.text('Sair da conta'), findsNothing);
      expect(find.text('Administração'), findsNothing);
      expect(find.text('ana@example.invalid'), findsNothing);
    },
  );

  testWidgets('privacy link is omitted when not configured or not HTTPS', (
    tester,
  ) async {
    final user = ProfileTestUser(
      providerData: [ProfileTestProvider('password')],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileView(count: 0, user: user),
      ),
    );
    expect(find.text('Política de privacidade'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileView(
          count: 0,
          user: user,
          privacyPolicyUrl: 'javascript:alert(1)',
        ),
      ),
    );
    expect(find.text('Política de privacidade'), findsNothing);
  });
}
