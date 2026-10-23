import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_firebase_bootstrap.dart';
import 'package:tudo_aqui_macacu/core/config/local_network_isolation.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';

void main() {
  test(
    'Auth diagnostics are opt-in and restricted to the local demo build',
    () {
      expect(
        resolveLocalAuthEmulatorPort(
          diagnosticsEnabled: false,
          localSearchEnabled: false,
          debugBuild: false,
          projectId: 'tudo-aqui-macacu',
          host: 'firebaseapp.com',
        ),
        9097,
      );
      expect(
        resolveLocalAuthEmulatorPort(
          diagnosticsEnabled: true,
          localSearchEnabled: true,
          debugBuild: true,
          projectId: 'demo-universal-search',
          host: '127.0.0.1',
        ),
        9197,
      );
      for (final invalid in [
        (
          local: false,
          debug: true,
          project: 'demo-universal-search',
          host: '127.0.0.1',
        ),
        (
          local: true,
          debug: false,
          project: 'demo-universal-search',
          host: '127.0.0.1',
        ),
        (
          local: true,
          debug: true,
          project: 'tudo-aqui-macacu',
          host: '127.0.0.1',
        ),
        (
          local: true,
          debug: true,
          project: 'demo-universal-search',
          host: '10.0.2.2',
        ),
      ]) {
        expect(
          () => resolveLocalAuthEmulatorPort(
            diagnosticsEnabled: true,
            localSearchEnabled: invalid.local,
            debugBuild: invalid.debug,
            projectId: invalid.project,
            host: invalid.host,
          ),
          throwsStateError,
        );
      }
    },
  );

  test(
    'local bootstrap configures isolation and emulators before probes',
    () async {
      final completed = <String>[];
      Future<void> record(String name) async => completed.add(name);

      await runLocalFirebaseBootstrap(
        establishNetworkIsolation: () => record('isolation'),
        initializeDemoProject: () => record('demo-project'),
        configureAuthEmulator: () => record('auth'),
        configureFirestoreSettings: () => record('firestore-settings'),
        configureFirestoreEmulator: () => record('firestore-emulator'),
        configureFunctionsEmulators: () => record('functions'),
        prepareLocalAppCheck: () => record('app-check'),
        validateLocalAuthSession: () => record('auth-validation'),
        validateLocalServices: () => record('service-probes'),
      );

      expect(completed, [
        'isolation',
        'demo-project',
        'auth',
        'firestore-settings',
        'firestore-emulator',
        'functions',
        'app-check',
        'auth-validation',
        'service-probes',
      ]);
    },
  );

  test(
    'local bootstrap stops immediately when an emulator stage fails',
    () async {
      final completed = <String>[];
      Future<void> record(String name) async => completed.add(name);

      await expectLater(
        runLocalFirebaseBootstrap(
          establishNetworkIsolation: () => record('isolation'),
          initializeDemoProject: () => record('demo-project'),
          configureAuthEmulator: () => record('auth'),
          configureFirestoreSettings: () => record('firestore-settings'),
          configureFirestoreEmulator: () async {
            completed.add('firestore-emulator');
            throw StateError('emulator unavailable');
          },
          configureFunctionsEmulators: () => record('functions'),
          prepareLocalAppCheck: () => record('app-check'),
          validateLocalAuthSession: () => record('auth-validation'),
          validateLocalServices: () => record('service-probes'),
        ),
        throwsStateError,
      );

      expect(completed, [
        'isolation',
        'demo-project',
        'auth',
        'firestore-settings',
        'firestore-emulator',
      ]);
    },
  );

  test('network isolation failure prevents Firebase initialization', () async {
    final completed = <String>[];

    await expectLater(
      runLocalFirebaseBootstrap(
        establishNetworkIsolation: () async {
          completed.add('isolation');
          throw StateError('VPN unavailable');
        },
        initializeDemoProject: () async => completed.add('demo-project'),
        configureAuthEmulator: () async => completed.add('auth'),
        configureFirestoreSettings: () async =>
            completed.add('firestore-settings'),
        configureFirestoreEmulator: () async =>
            completed.add('firestore-emulator'),
        configureFunctionsEmulators: () async => completed.add('functions'),
        prepareLocalAppCheck: () async => completed.add('app-check'),
        validateLocalAuthSession: () async => completed.add('auth-validation'),
        validateLocalServices: () async => completed.add('service-probes'),
      ),
      throwsStateError,
    );

    expect(completed, ['isolation']);
  });

  test('missing diagnostic proxy blocks Firebase initialization', () async {
    final completed = <String>[];

    await expectLater(
      runLocalFirebaseBootstrap(
        establishNetworkIsolation: () => verifyLocalAuthDiagnosticProxy(
          enabled: true,
          host: '127.0.0.1',
          port: 9197,
          probe: (_, _) async => throw const SocketException('private detail'),
        ),
        initializeDemoProject: () async => completed.add('firebase'),
        configureAuthEmulator: () async => completed.add('auth'),
        configureFirestoreSettings: () async =>
            completed.add('firestore-settings'),
        configureFirestoreEmulator: () async => completed.add('firestore'),
        configureFunctionsEmulators: () async => completed.add('functions'),
        prepareLocalAppCheck: () async => completed.add('app-check'),
        validateLocalAuthSession: () async => completed.add('auth-validation'),
        validateLocalServices: () async => completed.add('probes'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'sanitized message',
          isNot(contains('private detail')),
        ),
      ),
    );

    expect(completed, isEmpty);
  });

  test(
    'Firestore must retain the explicit local endpoint and disabled cache',
    () {
      expect(
        isLocalFirestoreConfiguration(
          host: '127.0.0.1:8087',
          sslEnabled: false,
          persistenceEnabled: false,
          expectedHost: '127.0.0.1:8087',
        ),
        isTrue,
      );
      expect(
        isLocalFirestoreConfiguration(
          host: 'firestore.googleapis.com',
          sslEnabled: true,
          persistenceEnabled: false,
          expectedHost: '127.0.0.1:8087',
        ),
        isFalse,
      );
    },
  );

  test('invalid local refresh token errors are recognized safely', () {
    expect(isInvalidLocalAuthSessionCode('INVALID_REFRESH_TOKEN'), isTrue);
    expect(isInvalidLocalAuthSessionCode('invalid-user-token'), isTrue);
    expect(isInvalidLocalAuthSessionCode('permission-denied'), isFalse);
    expect(
      shouldRenewLocalAnonymousSession(code: 'unknown', isAnonymous: true),
      isTrue,
    );
    expect(
      shouldRenewLocalAnonymousSession(code: 'unknown', isAnonymous: false),
      isFalse,
    );
    expect(
      localSearchStartupMessage(const LocalSearchSessionExpired()),
      contains('Nenhum dado foi apagado'),
    );
    expect(isInvalidLocalAuthSessionCode('unknown'), isFalse);
  });

  test(
    'searchLocal never auto-replaces a restored session after Auth failure',
    () {
      expect(
        shouldAutomaticallyRenewAnonymousSession(
          searchLocalEnabled: true,
          code: 'unknown',
          isAnonymous: true,
        ),
        isFalse,
      );
      expect(
        shouldAutomaticallyRenewAnonymousSession(
          searchLocalEnabled: true,
          code: 'INVALID_REFRESH_TOKEN',
          isAnonymous: true,
        ),
        isFalse,
      );
      expect(
        shouldAutomaticallyRenewAnonymousSession(
          searchLocalEnabled: false,
          code: 'unknown',
          isAnonymous: true,
        ),
        isTrue,
      );
    },
  );

  test(
    'legacy non-searchLocal helper still refuses registered replacement',
    () async {
      var signedOut = false;
      await expectLater(
        renewExpiredLocalVisitor<String>(
          wasAnonymous: false,
          signOut: () async => signedOut = true,
          signInAnonymously: () async => 'unexpected-visitor',
        ),
        throwsA(isA<LocalSearchSessionExpired>()),
      );
      expect(signedOut, isFalse);
    },
  );

  test(
    'Auth validation failure stops later service probes and is recoverable',
    () async {
      final completed = <String>[];
      await expectLater(
        runLocalFirebaseBootstrap(
          establishNetworkIsolation: () async => completed.add('isolation'),
          initializeDemoProject: () async => completed.add('project'),
          configureAuthEmulator: () async => completed.add('auth-emulator'),
          configureFirestoreSettings: () async =>
              completed.add('firestore-settings'),
          configureFirestoreEmulator: () async => completed.add('firestore'),
          configureFunctionsEmulators: () async => completed.add('functions'),
          prepareLocalAppCheck: () async => completed.add('app-check'),
          validateLocalAuthSession: () async => throw StateError('auth failed'),
          validateLocalServices: () async =>
              completed.add('protected-service-probes'),
        ),
        throwsA(isA<LocalAuthBootstrapFailure>()),
      );

      expect(completed, [
        'isolation',
        'project',
        'auth-emulator',
        'firestore-settings',
        'firestore',
        'functions',
        'app-check',
      ]);
    },
  );
}
