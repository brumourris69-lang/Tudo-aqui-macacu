import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:tudo_aqui_macacu/core/auth/admin_authorization.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/content/hybrid_admin_establishments_repository.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const _adminEmail = String.fromEnvironment('LOCAL_ADMIN_TEST_EMAIL');
const _adminPassword = String.fromEnvironment('LOCAL_ADMIN_TEST_PASSWORD');
const _endpoint = String.fromEnvironment('HYBRID_ADMIN_ENDPOINT');
final _configured =
    LocalSearchEnvironment.enabled &&
    LocalSearchEnvironment.project == 'demo-universal-search' &&
    LocalSearchEnvironment.host == '127.0.0.1' &&
    HybridAdminRuntime.enabled &&
    _endpoint == 'http://127.0.0.1:5077/functions/v1/manage-establishments' &&
    _adminEmail.endsWith('@example.invalid') &&
    _adminPassword.length >= 12;

Future<T> _stage<T>(String name, Future<T> Function() action) async {
  debugPrint('HYBRID_E2E_START:$name');
  try {
    final result = await action().timeout(const Duration(seconds: 25));
    debugPrint('HYBRID_E2E_OK:$name');
    return result;
  } on TimeoutException {
    debugPrint('HYBRID_E2E_TIMEOUT:$name');
    rethrow;
  } on FirebaseException catch (error) {
    debugPrint('HYBRID_E2E_FIREBASE_ERROR:$name:${error.code}');
    rethrow;
  } catch (error) {
    debugPrint('HYBRID_E2E_ERROR:$name:${error.runtimeType}');
    rethrow;
  }
}

class _FixedTokenSource implements FirebaseIdTokenSource {
  const _FixedTokenSource(this.token);

  final String? token;

  @override
  bool get isAnonymous => false;

  @override
  Future<String?> getIdToken() async => token;
}

class _FirestoreDocument {
  const _FirestoreDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

Future<_FirestoreDocument?> _readFirestoreDocument({
  required FirebaseFirestore firestore,
  required String collection,
  required String documentId,
}) async {
  final snapshot = await firestore
      .collection(collection)
      .doc(documentId)
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 10));
  if (!snapshot.exists) return null;
  return _FirestoreDocument(id: snapshot.id, data: snapshot.data()!);
}

Future<List<_FirestoreDocument>> _listFirestoreDocuments({
  required FirebaseFirestore firestore,
  required String collection,
}) async {
  final snapshot = await firestore
      .collection(collection)
      .get(const GetOptions(source: Source.server))
      .timeout(const Duration(seconds: 20));
  return snapshot.docs
      .map(
        (document) =>
            _FirestoreDocument(id: document.id, data: document.data()),
      )
      .toList(growable: false);
}

Future<void> _openEditor(
  WidgetTester tester, {
  DocumentSnapshot<Map<String, dynamic>>? document,
  Map<String, Object?>? initialDocumentData,
  String? initialDocumentId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ContentEditor(
                  collection: 'establishments',
                  doc: document,
                  initialDocumentData: initialDocumentData?.cast(),
                  initialDocumentId: initialDocumentId,
                ),
              ),
            ),
            child: const Text('Abrir editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'authenticated Admin editor and importer use the demo bridge and Firestore V2 Rules',
    (tester) async {
      if (!_configured) {
        fail('Required demo-only integration defines are missing or invalid.');
      }
      if (!Platform.isAndroid) {
        fail(
          'This end-to-end target must run on the authorized Android Emulator.',
        );
      }

      // The native searchLocal VPN must be active before Firebase initialization.
      await _stage('vpn.prepare', LocalNetworkIsolation.prepare);
      LocalSearchEnvironment.requireDemo('demo-universal-search');
      await _stage(
        'firebase.initialize',
        () => Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'demo-emulator-api-key',
            appId: '1:000000000000:android:demo',
            messagingSenderId: '000000000000',
            projectId: 'demo-universal-search',
          ),
        ),
      );

      final auth = FirebaseAuth.instance;
      auth.useAuthEmulator('127.0.0.1', 9097, automaticHostMapping: false);
      final firestore = FirebaseFirestore.instance;
      firestore.settings = const Settings(persistenceEnabled: false);
      // Keep Android loopback intact so adb reverse can carry native gRPC to
      // the host. The plugin's automatic mapping to 10.0.2.2 is captured by
      // the searchLocal sink VPN and was the source of the prior UNAVAILABLE.
      firestore.useFirestoreEmulator(
        '127.0.0.1',
        8087,
        automaticHostMapping: false,
      );
      FirebaseFunctions.instance.useFunctionsEmulator('127.0.0.1', 5007);

      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      final credential = await _stage(
        'auth.admin.sign_in',
        () => auth.signInWithEmailAndPassword(
          email: _adminEmail,
          password: _adminPassword,
        ),
      );
      final user = credential.user!;
      addTearDown(() => auth.signOut());
      expect(user.isAnonymous, isFalse);
      final tokenResult = await _stage(
        'auth.admin.claims',
        () => user.getIdTokenResult(true),
      );
      final claims = tokenResult.claims;
      expect(claims?['admin'], isTrue);
      expect(claims?['adminVersion'], isA<String>());
      final adminAuthorization = AdminAuthorization.instance;
      await _stage('admin.authorization.listen', adminAuthorization.start);
      await _stage('admin.authorization.callable', () async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(deadline)) {
          if (adminAuthorization.allows(user)) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw TimeoutException('Admin callable did not grant UI capability.');
      });
      expect(adminAuthorization.allows(user), isTrue);
      expect(isAdminUser(user), isTrue);
      final callableAuthorization = await _stage(
        'firestore.sdk.admin_authorization_get',
        () => firestore
            .collection('admin_authorizations')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
      );
      expect(callableAuthorization.data()?['enabled'], isTrue);
      expect(callableAuthorization.data()?['pending'], isFalse);
      expect(callableAuthorization.data()?['version'], claims?['adminVersion']);

      // Exercise getAfter() using the Android Firestore SDK itself, not REST
      // or Admin SDK. The reverse is exact-port and stays on device loopback.
      final sdkEntityId = 'sdk-native-$suffix';
      final sdkOperationId = newHybridAdminRequestId();
      final sdkBatch = firestore.batch();
      sdkBatch.set(firestore.collection('establishments').doc(sdkEntityId), {
        'name': 'Estabelecimento SDK fictício',
        'title': 'Estabelecimento SDK fictício',
        'category': 'Comércio',
        'subcategory': 'Demonstração',
        'description': 'Fixture gravada pelo SDK nativo.',
        'shortDescription': 'Fixture SDK.',
        'location': 'Local de demonstração',
        'address': '',
        'published': true,
        'active': true,
        'featured': false,
        'publicContactApproved': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'catalogVersion': 1,
        'outboxOperationId': sdkOperationId,
      });
      sdkBatch.set(firestore.collection('catalog_outbox').doc(sdkOperationId), {
        'schemaVersion': 2,
        'operationId': sdkOperationId,
        'entityType': 'establishment',
        'entityId': sdkEntityId,
        'authorUid': user.uid,
        'version': 1,
        'operation': 'reconcile',
        'state': 'pending',
        'attemptCount': 0,
        'workerId': null,
        'leaseToken': null,
        'leaseExpiresAt': null,
        'nextAttemptAt': null,
        'lastErrorCode': null,
        'syncedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _stage(
        'firestore.sdk.atomic_pair_write',
        () => sdkBatch.commit().timeout(const Duration(seconds: 12)),
      );
      final sdkReadback = await _stage(
        'firestore.sdk.source_read',
        () => firestore
            .collection('establishments')
            .doc(sdkEntityId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
      );
      expect(sdkReadback.data()?['catalogVersion'], 1);
      expect(sdkReadback.data()?['outboxOperationId'], sdkOperationId);
      await expectLater(
        firestore
            .collection('establishments')
            .doc(sdkEntityId)
            .update({'name': 'Alteração sem evento pareado'})
            .timeout(const Duration(seconds: 10)),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      debugPrint('HYBRID_E2E_OK:firestore.sdk.unpaired_write_denied');
      await expectLater(
        firestore
            .collection('catalog_outbox')
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      debugPrint('HYBRID_E2E_OK:firestore.sdk.outbox_denied');

      final repository = HybridAdminRuntime.createIfEnabled();
      expect(repository, isNotNull);
      final service = repository!;

      // Exercise the real ContentEditor state and save handler against the bridge.
      final title = 'Integração fictícia $suffix';
      await _openEditor(tester);
      dynamic editor = tester.state(find.byType(ContentEditor));
      editor.title.text = title;
      editor.description.text = 'Cadastro temporário para teste local.';
      editor.category.text = 'Comércio';
      editor.location.text = 'Local de demonstração';
      await _stage(
        'content.create.save',
        () => tester.runAsync(() async => editor.save() as Future<void>),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final created = await _stage(
        'content.create.rules_readback',
        () => _listFirestoreDocuments(
          firestore: firestore,
          collection: 'establishments',
        ),
      );
      final matchingDocuments = created.where(
        (document) => document.data['title'] == title,
      );
      expect(matchingDocuments, hasLength(1));
      final createdDocument = matchingDocuments.single;
      final sourceId = createdDocument.id;
      var sourceDocument = createdDocument;
      var sourceData = sourceDocument.data;
      var data = sourceData;
      expect(data['catalogVersion'], 1);
      expect(
        data['outboxOperationId'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(data.containsKey('ownerEmail'), isFalse);

      // Update is exercised through ContentEditor, then verified at the source.
      await _openEditor(
        tester,
        initialDocumentId: sourceId,
        initialDocumentData: sourceData,
      );
      editor = tester.state(find.byType(ContentEditor));
      editor.title.text = '$title editado';
      await _stage(
        'content.update.save',
        () => tester.runAsync(() async => editor.save() as Future<void>),
      );
      await tester.pumpAndSettle();
      sourceDocument = (await _stage(
        'content.update.rules_readback',
        () => _readFirestoreDocument(
          firestore: firestore,
          collection: 'establishments',
          documentId: sourceId,
        ),
      ))!;
      sourceData = sourceDocument.data;
      expect(sourceData['catalogVersion'], 2);
      final operationAfterEdit = sourceData['outboxOperationId'];
      expect(operationAfterEdit, isA<String>());
      expect(operationAfterEdit, isNot(data['outboxOperationId']));

      await expectLater(
        service.update(
          requestId: newHybridAdminRequestId(),
          entityId: sourceId,
          expectedVersion: 1,
          data: const {'title': 'Versão antiga', 'name': 'Versão antiga'},
        ),
        throwsA(
          isA<HybridAdminException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.conflict,
          ),
        ),
      );

      final invalidClient = http.Client();
      addTearDown(invalidClient.close);
      final unavailableRepository =
          FirebaseSupabaseAdminEstablishmentsRepository(
            endpoint: Uri.parse(
              'http://127.0.0.1:5078/functions/v1/manage-establishments',
            ),
            tokenSource: CurrentFirebaseIdTokenSource(auth),
            client: invalidClient,
            timeout: const Duration(seconds: 2),
          );
      await expectLater(
        unavailableRepository.create(
          requestId: newHybridAdminRequestId(),
          entityId: 'unavailable-$suffix',
          data: const {'name': 'Indisponível', 'category': 'Comércio'},
        ),
        throwsA(
          isA<HybridAdminException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.unavailable,
          ),
        ),
      );

      final invalidTokenRepository =
          FirebaseSupabaseAdminEstablishmentsRepository(
            endpoint: Uri.parse(_endpoint),
            tokenSource: const _FixedTokenSource('synthetic-invalid-token'),
            client: http.Client(),
          );
      await expectLater(
        invalidTokenRepository.create(
          requestId: newHybridAdminRequestId(),
          entityId: 'invalid-token-$suffix',
          data: const {'name': 'Negado', 'category': 'Comércio'},
        ),
        throwsA(
          isA<HybridAdminException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.unauthenticated,
          ),
        ),
      );
      expect(
        await _readFirestoreDocument(
          firestore: firestore,
          collection: 'establishments',
          documentId: 'invalid-token-$suffix',
        ),
        isNull,
      );

      // The app never performs a physical delete. The V2 candidate Rules must
      // also deny a direct client delete even for an authorized Admin.
      await expectLater(
        firestore
            .collection('establishments')
            .doc(sourceId)
            .delete()
            .timeout(const Duration(seconds: 10)),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      debugPrint('HYBRID_E2E_OK:firestore.sdk.physical_delete_denied');

      var current = sourceData;
      await service.unpublish(
        requestId: newHybridAdminRequestId(),
        entityId: sourceId,
        expectedVersion: current['catalogVersion'] as int,
      );
      sourceDocument = (await _readFirestoreDocument(
        firestore: firestore,
        collection: 'establishments',
        documentId: sourceId,
      ))!;
      sourceData = sourceDocument.data;
      current = sourceData;
      expect(current['published'], isFalse);
      expect(current['deletedAt'], isNull);
      expect(current['catalogVersion'], 3);

      await service.republish(
        requestId: newHybridAdminRequestId(),
        entityId: sourceId,
        expectedVersion: current['catalogVersion'] as int,
        data: const {'published': true, 'active': true},
      );
      sourceDocument = (await _readFirestoreDocument(
        firestore: firestore,
        collection: 'establishments',
        documentId: sourceId,
      ))!;
      sourceData = sourceDocument.data;
      expect(sourceData['published'], isTrue);
      expect(sourceData['catalogVersion'], 4);

      await service.delete(
        requestId: newHybridAdminRequestId(),
        entityId: sourceId,
        expectedVersion: 4,
      );
      sourceDocument = (await _readFirestoreDocument(
        firestore: firestore,
        collection: 'establishments',
        documentId: sourceId,
      ))!;
      sourceData = sourceDocument.data;
      expect(sourceData['deletedAt'], isNotNull);
      expect(sourceData['catalogVersion'], 5);

      // Exercise the actual initial-importer widget. The Emulator starts empty,
      // so fixed modelo-* IDs are safe and remain recognizable by the importer.
      // The same capability returned by the real manageAdminJob callable is
      // used by the UI; no synthetic AdminAuthorization state is injected.
      expect(adminAuthorization.allows(user), isTrue);
      await tester.pumpWidget(
        const MaterialApp(home: InitialContentImporter()),
      );
      final dynamic importerState = tester.state(
        find.byType(InitialContentImporter),
      );
      await _stage(
        'importer.first_run',
        () => tester.runAsync(
          () async => importerState.importExamples() as Future<void>,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final importerMessages = tester.widgetList<SnackBar>(
        find.byType(SnackBar),
      );
      debugPrint('HYBRID_E2E_IMPORTER_SNACKBARS:${importerMessages.length}');
      final allImported = await _stage(
        'importer.rules_readback',
        () => _listFirestoreDocuments(
          firestore: firestore,
          collection: 'establishments',
        ),
      );
      final firstImport = allImported
          .where((document) => document.id.startsWith('modelo-'))
          .toList(growable: false);
      expect(firstImport.length, greaterThan(1));
      final importerSdkReadback = await _stage(
        'importer.sdk.source_read',
        () => firestore
            .collection('establishments')
            .doc('modelo-1')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
      );
      expect(importerSdkReadback.exists, isTrue);
      expect(importerSdkReadback.data()?['catalogVersion'], 1);
      for (final document in firstImport) {
        expect(document.id, startsWith('modelo-'));
        expect(document.data['catalogVersion'], 1);
        expect(document.data['outboxOperationId'], isA<String>());
      }
      final beforeReplay = {
        for (final document in firstImport)
          document.id: document.data['outboxOperationId'],
      };
      // The component's fixed seed is intentionally preserved. On an empty,
      // disposable Emulator it creates only fake modelo-* rows; no production
      // identity or data is used by this target.
      await _stage(
        'importer.replay',
        () => tester.runAsync(
          () async => importerState.importExamples() as Future<void>,
        ),
      );
      await tester.pumpAndSettle();
      final afterReplay = await _stage(
        'importer.replay_rules_readback',
        () => _listFirestoreDocuments(
          firestore: firestore,
          collection: 'establishments',
        ),
      );
      final replayedModels = afterReplay
          .where((document) => document.id.startsWith('modelo-'))
          .toList(growable: false);
      expect(replayedModels, hasLength(firstImport.length));
      for (final document in replayedModels) {
        expect(document.data['catalogVersion'], 1);
        expect(document.data['outboxOperationId'], beforeReplay[document.id]);
      }

      await auth.signOut();
      await _stage('admin.authorization.logout_denied', () async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (DateTime.now().isBefore(deadline)) {
          if (!adminAuthorization.value.allowed) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw TimeoutException('Logout did not clear Admin UI capability.');
      });
      final ordinaryEmail = 'ordinary-$suffix@example.invalid';
      final ordinary = await auth.createUserWithEmailAndPassword(
        email: ordinaryEmail,
        password: 'LocalOnly-$suffix-Aa1!',
      );
      await _stage('admin.authorization.ordinary_denied', () async {
        await adminAuthorization.updateUser(ordinary.user);
        expect(adminAuthorization.allows(ordinary.user), isFalse);
      });
      await expectLater(
        SecureBackend.invoke('manageAdminJob', const {
          'operation': 'list',
          'pageSize': 1,
        }),
        throwsA(isA<StateError>()),
      );
      debugPrint('HYBRID_E2E_OK:callable.ordinary_denied');
      await expectLater(
        firestore
            .collection('establishments')
            .doc(sdkEntityId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      debugPrint('HYBRID_E2E_OK:firestore.sdk.ordinary_read_denied');
      final ordinaryRepository = HybridAdminRuntime.createIfEnabled()!;
      await expectLater(
        ordinaryRepository.create(
          requestId: newHybridAdminRequestId(),
          entityId: 'ordinary-denied-$suffix',
          data: const {'name': 'Negado', 'category': 'Comércio'},
        ),
        throwsA(
          isA<HybridAdminException>().having(
            (error) => error.failure,
            'failure',
            HybridAdminFailure.permissionDenied,
          ),
        ),
      );
      await ordinary.user?.delete();

      // This optional account must be a throwaway demo Admin already revoked
      // through the trusted local claim-management script. No client grant
      // path is provided by the integration target.
      const revokedEmail = String.fromEnvironment('LOCAL_REVOKED_ADMIN_EMAIL');
      const revokedPassword = String.fromEnvironment(
        'LOCAL_REVOKED_ADMIN_PASSWORD',
      );
      if (revokedEmail.isNotEmpty && revokedPassword.length >= 12) {
        final revoked = await auth.signInWithEmailAndPassword(
          email: revokedEmail,
          password: revokedPassword,
        );
        await _stage('admin.authorization.revoked_denied', () async {
          await adminAuthorization.updateUser(revoked.user);
          expect(adminAuthorization.allows(revoked.user), isFalse);
        });
        await expectLater(
          HybridAdminRuntime.createIfEnabled()!.create(
            requestId: newHybridAdminRequestId(),
            entityId: 'revoked-denied-$suffix',
            data: const {'name': 'Negado', 'category': 'Comércio'},
          ),
          throwsA(
            isA<HybridAdminException>().having(
              (error) => error.failure,
              'failure',
              HybridAdminFailure.permissionDenied,
            ),
          ),
        );
        await auth.signOut();
      }
      const disabledEmail = String.fromEnvironment('LOCAL_DISABLED_TEST_EMAIL');
      const disabledPassword = String.fromEnvironment(
        'LOCAL_DISABLED_TEST_PASSWORD',
      );
      if (disabledEmail.isNotEmpty && disabledPassword.length >= 12) {
        await expectLater(
          auth.signInWithEmailAndPassword(
            email: disabledEmail,
            password: disabledPassword,
          ),
          throwsA(
            isA<FirebaseAuthException>().having(
              (error) => error.code,
              'code',
              'user-disabled',
            ),
          ),
        );
        expect(adminAuthorization.value.allowed, isFalse);
        debugPrint('HYBRID_E2E_OK:auth.disabled_denied');
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: !_configured,
  );
}
