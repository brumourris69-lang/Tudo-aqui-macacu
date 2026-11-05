import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tudo_aqui_macacu/core/auth/admin_authorization.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/core/widgets/app_brand.dart';
import 'package:tudo_aqui_macacu/core/config/spark_local_environment.dart';
import 'package:tudo_aqui_macacu/features/auth/email_password_auth.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const _captureKey = ValueKey<String>('account-admin-visual-capture');

class _VisualUser implements User {
  _VisualUser({required this.uid, this.isAnonymous = false});

  @override
  final String uid;
  @override
  final bool isAnonymous;
  @override
  String? get displayName => isAnonymous ? null : 'Conta de demonstração';
  @override
  String? get email => isAnonymous ? null : 'conta.fixture@example.invalid';
  @override
  String? get photoURL => null;
  @override
  List<UserInfo> get providerData => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final poppins = FontLoader('Poppins')
      ..addFont(_loadFont('Poppins-Regular.ttf'))
      ..addFont(_loadFont('Poppins-Medium.ttf'))
      ..addFont(_loadFont('Poppins-SemiBold.ttf'))
      ..addFont(_loadFont('Poppins-Bold.ttf'));
    await poppins.load();
    final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(icons))).load();
  });

  testWidgets('captures account, authentication and Admin screens', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    final authorization = AdminAuthorization()
      ..value = const AdminClaimState(uid: 'visual-admin', allowed: true);
    addTearDown(authorization.dispose);

    await _capture(
      tester,
      'minha-conta-visitante',
      child: ProfileView(
        count: 0,
        user: _VisualUser(uid: 'visitor', isAnonymous: true),
      ),
      size: const Size(360, 850),
    );
    expect(find.text('Administração'), findsNothing);
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      'minha-conta-admin',
      child: AdminAuthorizationScope(
        authorization: authorization,
        child: ProfileView(
          count: 2,
          agendaCount: 1,
          user: _VisualUser(uid: 'visual-admin'),
        ),
      ),
      size: const Size(360, 850),
    );
    expect(find.byKey(const Key('profile-admin-status')), findsOneWidget);
    expect(find.text('Administração'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Administração'));
    await tester.pumpAndSettle();
    expect(find.text('Área administrativa'), findsOneWidget);
    expect(find.text('Estabelecimentos'), findsOneWidget);
    expect(find.text('Conteúdo'), findsOneWidget);
    expect(find.text('Administração').evaluate().length, 2);
    expect(find.text('Configurações'), findsNothing);
    await _expectGolden(tester, 'painel-administracao');
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      'login-google',
      child: const GoogleLoginView(),
      size: const Size(360, 850),
    );
    expect(tester.takeException(), isNull);

    await _capture(
      tester,
      'login-email',
      child: EmailPasswordAuthView(
        signIn: (_, _) async {},
        register: (_, _, _) async {},
        resetPassword: (_) async {},
        onAuthenticated: () async {},
      ),
      size: const Size(360, 850),
    );
    expect(find.byKey(const Key('auth-email')), findsOneWidget);
    expect(find.byKey(const Key('auth-reset-password')), findsOneWidget);
    expect(find.text('Macacu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin visual tools still require the matching authorized UID', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    final authorization = AdminAuthorization()
      ..value = const AdminClaimState(uid: 'authorized-fixture', allowed: true);
    addTearDown(authorization.dispose);

    Widget account(String uid) => AdminAuthorizationScope(
      authorization: authorization,
      child: MaterialApp(
        theme: AppTheme.light,
        home: ProfileView(count: 0, user: _VisualUser(uid: uid)),
      ),
    );

    await tester.pumpWidget(account('ordinary-fixture'));
    expect(find.text('Administração'), findsNothing);
    expect(find.byKey(const Key('profile-admin-status')), findsNothing);

    await tester.pumpWidget(account('authorized-fixture'));
    expect(find.text('Administração'), findsOneWidget);
    expect(find.byKey(const Key('profile-admin-status')), findsOneWidget);

    authorization.value = const AdminClaimState(
      uid: 'authorized-fixture',
      allowed: false,
    );
    await tester.pump();
    expect(find.text('Administração'), findsNothing);
    expect(find.byKey(const Key('profile-admin-status')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account, Admin panel and login fit narrow and enlarged layouts',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      final authorization = AdminAuthorization()
        ..value = const AdminClaimState(uid: 'visual-admin', allowed: true);
      addTearDown(authorization.dispose);

      final cases = <(String, Widget)>[
        (
          'conta',
          AdminAuthorizationScope(
            authorization: authorization,
            child: ProfileView(
              count: 4,
              user: _VisualUser(uid: 'visual-admin'),
            ),
          ),
        ),
        ('painel', const AdminView()),
        (
          'login',
          EmailPasswordAuthView(
            signIn: (_, _) async {},
            register: (_, _, _) async {},
            resetPassword: (_) async {},
            onAuthenticated: () async {},
          ),
        ),
      ];
      for (final width in [320.0, 360.0, 412.0]) {
        for (final scale in [1.0, 1.5]) {
          for (final (name, child) in cases) {
            await _capture(
              tester,
              '$name-${width.toInt()}-$scale',
              child: child,
              size: Size(width, 900),
              textScale: scale,
              writeGolden: false,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$name em ${width.toInt()} px, texto $scale',
            );
          }
        }
      }
    },
  );
}

Future<ByteData> _loadFont(String name) async => ByteData.sublistView(
  await File('assets/fonts/local-poppins/$name').readAsBytes(),
);

Future<void> _capture(
  WidgetTester tester,
  String name, {
  required Widget child,
  required Size size,
  double textScale = 1,
  bool writeGolden = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('account-admin-capture-$name'),
      theme: AppTheme.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: _captureKey, child: app!),
      ),
      home: child,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  final brand = find.byType(AppBrand);
  if (brand.evaluate().isNotEmpty) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/tudo-aqui-macacu-icon-v1.png'),
        tester.element(brand.first),
      ),
    );
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  if (writeGolden) await _expectGolden(tester, name);
}

Future<void> _expectGolden(WidgetTester tester, String name) {
  final flavorSpecificName =
      SparkLocalEnvironment.enabled &&
          (name == 'minha-conta-visitante' || name == 'login-google')
      ? '$name-spark-local'
      : name;
  return expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('goldens/checkpoint4/$flavorSpecificName.png'),
  );
}
