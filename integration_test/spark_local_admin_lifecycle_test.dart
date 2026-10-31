import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tudo_aqui_macacu/core/auth/admin_authorization.dart';
import 'package:tudo_aqui_macacu/core/config/beta_environment.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/config/spark_local_environment.dart';
import 'package:tudo_aqui_macacu/core/theme/app_theme.dart';
import 'package:tudo_aqui_macacu/features/businesses/models/business.dart';
import 'package:tudo_aqui_macacu/features/businesses/screens/business_profile.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const _adminEmail = String.fromEnvironment('SPARK_LOCAL_ADMIN_EMAIL');
const _adminPassword = String.fromEnvironment('SPARK_LOCAL_ADMIN_PASSWORD');
const _createdId = String.fromEnvironment('SPARK_LOCAL_CREATED_CONTENT_ID');
const _runId = String.fromEnvironment('SPARK_LOCAL_RUN_ID');

final _firestore = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_initializeIsolatedFirebase);

  testWidgets(
    'SparkLocal Home draft and establishment lifecycle use real UI and Firestore',
    (tester) async {
      await _signInAdmin();
      await _exerciseHomeEditor(tester);
      await _exerciseEstablishmentLifecycle(tester);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _initializeIsolatedFirebase() async {
  if (!SparkLocalEnvironment.enabled ||
      _adminEmail.isEmpty ||
      _adminPassword.isEmpty ||
      _runId.isEmpty ||
      !_createdId.startsWith('spark-local-$_runId-')) {
    throw StateError('SPARK_LOCAL_TEST_CONFIGURATION_INVALID');
  }

  await LocalNetworkIsolation.prepareSparkLocal();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-emulator-api-key',
      appId: '1:000000000000:android:spark-local-demo',
      messagingSenderId: '000000000000',
      projectId: SparkLocalEnvironment.project,
    ),
  );
  BetaEnvironment.markSparkLocalReady(
    actualProjectId: Firebase.app().options.projectId,
  );
  _firestore.settings = const Settings(persistenceEnabled: false);
  _auth.useAuthEmulator(
    SparkLocalEnvironment.host,
    SparkLocalEnvironment.authPort,
    automaticHostMapping: false,
  );
  _firestore.useFirestoreEmulator(
    SparkLocalEnvironment.host,
    SparkLocalEnvironment.firestorePort,
    automaticHostMapping: false,
  );
}

Future<void> _signInAdmin() async {
  final credential = await _auth.signInWithEmailAndPassword(
    email: _adminEmail,
    password: _adminPassword,
  );
  final user = credential.user;
  if (user == null) throw StateError('SPARK_LOCAL_ADMIN_SIGN_IN_FAILED');
  await user.getIdToken(true);
  await AdminAuthorization.instance.start();
  await AdminAuthorization.instance.updateUser(user, forceRefresh: true);
  await _waitFor(() => AdminAuthorization.instance.allows(user));
}

Future<void> _exerciseHomeEditor(WidgetTester tester) async {
  debugPrint('SPARK16_STAGE:home_admin_start');
  final admin = _auth.currentUser;
  if (!AdminAuthorization.instance.allows(admin)) {
    throw StateError('SPARK_LOCAL_ADMIN_AUTHORIZATION_MISSING');
  }
  await _pumpHome(tester, admin);
  await _waitForWidget(tester, find.text('Tudo Aqui Macacu — Spark local'));

  for (var cycle = 0; cycle < 3; cycle++) {
    await _startHomeTitleEditing(tester);
    await _waitForWidget(tester, find.text('Editar título'));
    await tester.enterText(
      find.byKey(const ValueKey('home-title-editor-input')),
      'Rascunho Home que não deve aparecer',
    );
    await tester.tap(find.byKey(const ValueKey('home-title-editor-complete')));
    await tester.pump(const Duration(milliseconds: 300));
    await _ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey('home-admin-save-draft')),
    );
    await _waitFor(
      () async =>
          (await _firestore.doc('home_pages/draft').get())
              .data()?['heroTitle'] ==
          'Rascunho Home que não deve aparecer',
    );
    final published = await _firestore.doc('home_pages/published').get();
    expect(published.data()?['heroTitle'], 'Tudo Aqui Macacu — Spark local');
    await _ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey('home-admin-exit-editing')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollHomeToTop(tester);
    await _waitForWidget(tester, find.text('Tudo Aqui Macacu — Spark local'));
    debugPrint('SPARK16_STAGE:home_draft_exit_cycle_${cycle + 1}');
  }

  await _startHomeTitleEditing(tester);
  await _waitForWidget(tester, find.text('Editar título'));
  await tester.enterText(
    find.byKey(const ValueKey('home-title-editor-input')),
    'O que você procura hoje?Local',
  );
  await tester.tap(find.byKey(const ValueKey('home-title-editor-complete')));
  await tester.pump(const Duration(milliseconds: 300));
  await _ensureVisibleAndTap(
    tester,
    find.byKey(const ValueKey('home-admin-publish')),
  );
  await _waitFor(
    () async =>
        (await _firestore.doc('home_pages/published').get())
            .data()?['heroTitle'] ==
        'O que você procura hoje?Local',
  );
  debugPrint('SPARK16_STAGE:home_published_verified');
  await _ensureVisibleAndTap(
    tester,
    find.byKey(const ValueKey('home-admin-exit-editing')),
  );
  await tester.pump(const Duration(milliseconds: 300));

  await _auth.signOut();
  await AdminAuthorization.instance.updateUser(null);
  await _pumpHome(tester, null);
  await _waitForWidget(tester, find.text('O que você procura hoje?Local'));
  expect(find.byTooltip('Editar Home'), findsNothing);
  expect(find.text('Rascunho Home que não deve aparecer'), findsNothing);
  debugPrint('SPARK16_STAGE:home_visitor_verified');
}

Future<void> _startHomeTitleEditing(WidgetTester tester) async {
  await _scrollHomeToTop(tester);
  await _ensureVisibleAndTap(
    tester,
    find.byKey(const ValueKey('home-admin-toggle-hero-edit')),
  );
  final title = find.text('Toque para editar');
  final editTitle = find.byKey(const ValueKey('home-hero-title-edit'));
  await _waitForWidget(tester, title);
  await _ensureVisibleAndTap(tester, editTitle); // Starts the edit session.
  await tester.pump(const Duration(milliseconds: 250));
  await _ensureVisibleAndTap(tester, editTitle); // Opens the title editor.
}

Future<void> _scrollHomeToTop(WidgetTester tester) async {
  final homeScroll = find.byKey(const ValueKey('home-public-scroll-view'));
  if (homeScroll.evaluate().isEmpty) return;
  await tester.drag(homeScroll, const Offset(0, 1600));
  await tester.pumpAndSettle();
}

Future<void> _exerciseEstablishmentLifecycle(WidgetTester tester) async {
  debugPrint('SPARK16_STAGE:establishment_create_start');
  await _signInAdmin();
  expect(
    (await _firestore.doc('establishments/$_createdId').get()).exists,
    isFalse,
  );
  await _pumpEditorLauncher(tester, initialData: const {});
  await tester.tap(find.byKey(const ValueKey('open-content-editor')));
  await tester.pump(const Duration(milliseconds: 400));
  await _waitForWidget(tester, find.text('Editar estabelecimento'));
  await tester.enterText(
    find.byKey(const ValueKey('content-editor-primary-name')),
    'Comércio SparkLocal AVD',
  );
  await tester.tap(
    find.byKey(const ValueKey('content-editor-business-category')),
  );
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(
    find.byKey(const ValueKey('content-editor-category-option-Comércio')),
  );
  await tester.pump(const Duration(milliseconds: 250));
  await _saveEditor(tester);

  var canonical = await _firestore.doc('establishments/$_createdId').get();
  expect(canonical.exists, isTrue);
  expect(canonical.data()?['name'], 'Comércio SparkLocal AVD');
  expect(canonical.data()?['published'], isFalse);
  expect(await _readPublicProjection(), isNull);
  debugPrint('SPARK16_STAGE:establishment_draft_verified');

  await _pumpEditorLauncher(tester, initialData: canonical.data()!);
  await tester.tap(find.byKey(const ValueKey('open-content-editor')));
  await tester.pump(const Duration(milliseconds: 400));
  await _waitForWidget(tester, find.text('Editar estabelecimento'));
  await tester.enterText(
    find.byKey(const ValueKey('content-editor-primary-name')),
    'Comércio SparkLocal editado',
  );
  final publishToggle = find.byKey(
    const ValueKey('content-editor-published-toggle'),
  );
  await tester.ensureVisible(publishToggle);
  await tester.tap(publishToggle);
  await tester.pump(const Duration(milliseconds: 250));
  await _saveEditor(tester);

  canonical = await _firestore.doc('establishments/$_createdId').get();
  expect(canonical.data()?['name'], 'Comércio SparkLocal editado');
  expect(canonical.data()?['published'], isTrue);
  final publicData = await _readPublicProjection();
  expect(publicData?['name'], 'Comércio SparkLocal editado');
  debugPrint('SPARK16_STAGE:establishment_published_verified');

  await _auth.signOut();
  await AdminAuthorization.instance.updateUser(null);
  await _pumpPublicBusiness(tester, publicData!);
  expect(find.text('Comércio SparkLocal editado'), findsOneWidget);
  expect(find.byTooltip('Editar estabelecimento'), findsNothing);
  debugPrint('SPARK16_STAGE:establishment_visitor_verified');
  await _auth.signInWithEmailAndPassword(
    email: _adminEmail,
    password: _adminPassword,
  );
  await _auth.currentUser!.getIdToken(true);
  await AdminAuthorization.instance.updateUser(
    _auth.currentUser,
    forceRefresh: true,
  );
  await _waitFor(() => AdminAuthorization.instance.allows(_auth.currentUser));

  canonical = await _firestore.doc('establishments/$_createdId').get();
  await _pumpAdminBusinessProfile(tester, canonical.data()!);
  await tester.tap(find.byTooltip('Editar estabelecimento'));
  await tester.pump(const Duration(milliseconds: 350));
  await _waitForWidget(tester, find.text('Editar estabelecimento'));
  await tester.enterText(
    find.byKey(const ValueKey('content-editor-primary-name')),
    'Comércio SparkLocal revisado',
  );
  await _saveEditor(
    tester,
    returnedTo: find.byTooltip('Editar estabelecimento'),
  );
  canonical = await _firestore.doc('establishments/$_createdId').get();
  expect(canonical.data()?['name'], 'Comércio SparkLocal revisado');
  expect(
    (await _readPublicProjection())?['name'],
    'Comércio SparkLocal revisado',
  );
  debugPrint('SPARK16_STAGE:establishment_detail_edit_verified');

  await _pumpEditorLauncher(tester, initialData: canonical.data()!);
  await tester.tap(find.byKey(const ValueKey('open-content-editor')));
  await tester.pump(const Duration(milliseconds: 350));
  await _waitForWidget(tester, find.text('Editar estabelecimento'));
  final unpublishToggle = find.byKey(
    const ValueKey('content-editor-published-toggle'),
  );
  await tester.ensureVisible(unpublishToggle);
  await tester.tap(unpublishToggle);
  await tester.pump(const Duration(milliseconds: 200));
  await _saveEditor(tester);
  canonical = await _firestore.doc('establishments/$_createdId').get();
  expect(canonical.data()?['published'], isFalse);
  expect(await _readPublicProjection(), isNull);
  debugPrint('SPARK16_STAGE:establishment_unpublish_verified');

  await _pumpEditorLauncher(tester, initialData: canonical.data()!);
  await tester.tap(find.byKey(const ValueKey('open-content-editor')));
  await tester.pump(const Duration(milliseconds: 350));
  await _waitForWidget(tester, find.text('Editar estabelecimento'));
  final delete = find.byKey(const ValueKey('content-editor-delete'));
  await tester.ensureVisible(delete);
  await tester.tap(delete);
  await tester.pump(const Duration(milliseconds: 250));
  await _waitForWidget(tester, find.text('Excluir conteúdo?'));
  await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
  await tester.pump(const Duration(milliseconds: 300));
  await _waitFor(
    () async =>
        (await _firestore.doc('establishments/$_createdId').get())
            .data()?['deleted'] ==
        true,
  );
  canonical = await _firestore.doc('establishments/$_createdId').get();
  expect(canonical.data()?['deleted'], isTrue);
  expect(await _readPublicProjection(), isNull);
  debugPrint('SPARK16_STAGE:establishment_soft_delete_verified');
}

Future<Map<String, dynamic>?> _readPublicProjection() async {
  final snapshot = await _firestore
      .collection('beta_public_catalog/establishments/items')
      .where('visibility', isEqualTo: 'public')
      .where('sourceId', isEqualTo: _createdId)
      .limit(1)
      .get(const GetOptions(source: Source.server));
  if (snapshot.docs.isEmpty) return null;
  return snapshot.docs.single.data()['publicData'] as Map<String, dynamic>?;
}

Future<void> _pumpHome(WidgetTester tester, User? user) async {
  await tester.pumpWidget(
    AdminAuthorizationScope(
      authorization: AdminAuthorization.instance,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: HomeView(
            saved: const <String>{},
            favorite: (_) {},
            showExplore: () {},
            user: user,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpEditorLauncher(
  WidgetTester tester, {
  required Map<String, dynamic> initialData,
}) async {
  await tester.pumpWidget(
    AdminAuthorizationScope(
      authorization: AdminAuthorization.instance,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open-content-editor'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ContentEditor(
                      collection: 'establishments',
                      initialDocumentId: _createdId,
                      initialDocumentData: initialData,
                    ),
                  ),
                ),
                child: const Text('Abrir editor administrativo'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpPublicBusiness(
  WidgetTester tester,
  Map<String, dynamic> publicData,
) async {
  await tester.pumpWidget(
    AdminAuthorizationScope(
      authorization: AdminAuthorization.instance,
      child: MaterialApp(
        theme: AppTheme.light,
        home: BusinessProfile(
          business: Business.fromData(_createdId, publicData),
          saved: false,
          onFavorite: () {},
        ),
      ),
    ),
  );
  await _waitForWidget(tester, find.text(publicData['name'] as String));
}

Future<void> _pumpAdminBusinessProfile(
  WidgetTester tester,
  Map<String, dynamic> canonical,
) async {
  await tester.pumpWidget(
    AdminAuthorizationScope(
      authorization: AdminAuthorization.instance,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => BusinessProfile(
            business: Business.fromData(_createdId, canonical),
            saved: false,
            canEdit: AdminAuthorization.instance.allows(_auth.currentUser),
            onFavorite: () {},
            onEdit: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ContentEditor(
                  collection: 'establishments',
                  initialDocumentId: _createdId,
                  initialDocumentData: canonical,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _waitForWidget(tester, find.text(canonical['name'] as String));
}

Future<void> _saveEditor(WidgetTester tester, {Finder? returnedTo}) async {
  final save = find.byKey(const ValueKey('content-editor-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pump(const Duration(milliseconds: 250));
  await _waitForWidget(
    tester,
    returnedTo ?? find.byKey(const ValueKey('open-content-editor')),
  );
}

Future<void> _ensureVisibleAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _waitForWidget(WidgetTester tester, Finder finder) async {
  await _waitFor(() async {
    await tester.pump(const Duration(milliseconds: 80));
    return finder.evaluate().isNotEmpty;
  }, timeout: const Duration(seconds: 35));
}

Future<void> _waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  throw TimeoutException('SPARK_LOCAL_INTEGRATION_STAGE_TIMEOUT');
}
