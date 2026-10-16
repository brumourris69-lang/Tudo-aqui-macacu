import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/local_firebase_bootstrap.dart';

void main() {
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
        validateLocalServices: () async => completed.add('service-probes'),
      ),
      throwsStateError,
    );

    expect(completed, ['isolation']);
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
      localSearchStartupMessage(const LocalSearchSessionExpired()),
      contains('Nenhum dado foi apagado'),
    );
    expect(
      shouldRenewLocalAnonymousSession(code: 'unknown', isAnonymous: true),
      isTrue,
    );
    expect(
      shouldRenewLocalAnonymousSession(code: 'unknown', isAnonymous: false),
      isFalse,
    );
    expect(
      shouldRenewLocalAnonymousSession(
        code: 'permission-denied',
        isAnonymous: true,
      ),
      isFalse,
    );
  });

  test('renews only an invalid anonymous local session', () async {
    final calls = <String>[];
    final user = await renewExpiredLocalVisitor<String>(
      wasAnonymous: true,
      signOut: () async => calls.add('signOut'),
      signInAnonymously: () async {
        calls.add('anonymous');
        return 'new-local-visitor';
      },
    );
    expect(user, 'new-local-visitor');
    expect(calls, ['signOut', 'anonymous']);
  });

  test('never replaces a registered session with a local visitor', () async {
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
  });
}
