import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/auth/account_deletion_service.dart';

class _Gateway implements AccountDeletionGateway {
  _Gateway({
    this.account = const AccountDeletionAccount(
      uid: 'user-1',
      email: 'user@example.invalid',
      anonymous: false,
      providerIds: {'password'},
    ),
    this.admin = false,
    this.appleCode,
    this.failAt,
    this.failLocalCleanup = false,
  });

  final AccountDeletionAccount? account;
  final bool admin;
  final String? appleCode;
  String? failAt;
  final bool failLocalCleanup;
  final List<String> calls = [];

  @override
  Future<AccountDeletionAccount?> currentAccount() async {
    calls.add('identity');
    return account;
  }

  @override
  Future<bool> isAdministrator(String uid) async {
    calls.add('admin-check');
    return admin;
  }

  @override
  Future<AccountDeletionReauthentication> reauthenticate(
    AccountDeletionAccount account, {
    required Future<String?> Function() requestPassword,
  }) async {
    calls.add('reauthenticate');
    if (failAt == 'reauthenticate') throw StateError('provider');
    return AccountDeletionReauthentication(appleAuthorizationCode: appleCode);
  }

  @override
  Future<void> deletePersonalData(String uid) async {
    calls.add('firestore-delete');
    if (failAt == 'deletion-request-registered') {
      throw AccountDeletionException(
        'deletion_request_registered',
        retryAt: DateTime.utc(2030),
      );
    }
    if (failAt == 'contact-quota-active') {
      throw const AccountDeletionException('contact_quota_active');
    }
    if (failAt == 'firestore-delete') throw StateError('failed');
  }

  @override
  Future<void> clearLocalData(String uid) async {
    calls.add('local-delete');
    if (failAt == 'local-delete' || failLocalCleanup) {
      throw StateError('failed');
    }
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {
    calls.add('apple-revoke:$authorizationCode');
    if (failAt == 'apple-revoke') throw StateError('failed');
  }

  @override
  Future<void> deleteAuthAccount(String uid) async {
    calls.add('auth-delete');
    if (failAt == 'auth-delete') throw StateError('failed');
  }
}

void main() {
  test(
    'account deletion supports only a single configured Beta or Spark build',
    () {
      bool supported({
        bool beta = false,
        bool distribution = false,
        bool local = false,
        bool localSearch = false,
        bool staging = false,
      }) => FirebaseAccountDeletionGateway.supportsCurrentBuild(
        betaBuild: beta,
        sparkDistributionBuild: distribution,
        sparkLocalBuild: local,
        localSearchBuild: localSearch,
        stagingBuild: staging,
      );

      expect(supported(beta: true), isTrue);
      expect(supported(distribution: true), isTrue);
      expect(supported(), isFalse);
      expect(supported(beta: true, distribution: true), isFalse);
      expect(supported(beta: true, local: true), isFalse);
      expect(supported(distribution: true, local: true), isFalse);
      expect(supported(distribution: true, localSearch: true), isFalse);
      expect(supported(distribution: true, staging: true), isFalse);
    },
  );

  test('Auth and Firestore must use the same non-empty Firebase identity', () {
    expect(
      FirebaseAccountDeletionGateway.matchesFirebaseIdentity(
        authProjectId: 'demo-universal-search',
        firestoreProjectId: 'demo-universal-search',
        authAppId: 'demo-app-id',
        firestoreAppId: 'demo-app-id',
      ),
      isTrue,
    );
    expect(
      FirebaseAccountDeletionGateway.matchesFirebaseIdentity(
        authProjectId: 'demo-universal-search',
        firestoreProjectId: 'another-project',
        authAppId: 'demo-app-id',
        firestoreAppId: 'demo-app-id',
      ),
      isFalse,
    );
    expect(
      FirebaseAccountDeletionGateway.matchesFirebaseIdentity(
        authProjectId: 'demo-universal-search',
        firestoreProjectId: 'demo-universal-search',
        authAppId: 'demo-app-id',
        firestoreAppId: 'another-app-id',
      ),
      isFalse,
    );
    expect(
      FirebaseAccountDeletionGateway.matchesFirebaseIdentity(
        authProjectId: '',
        firestoreProjectId: '',
        authAppId: 'demo-app-id',
        firestoreAppId: 'demo-app-id',
      ),
      isFalse,
    );
  });

  test('provider selection supports password and Google without linking', () {
    expect(
      selectAccountDeletionProvider(
        providerIds: {'password'},
        isIos: false,
        appleConfigured: false,
      ),
      AccountDeletionProvider.password,
    );
    expect(
      selectAccountDeletionProvider(
        providerIds: {'google.com'},
        isIos: true,
        appleConfigured: false,
      ),
      AccountDeletionProvider.google,
    );
  });

  test(
    'Apple account requires configured iOS and is selected before others',
    () {
      expect(
        () => selectAccountDeletionProvider(
          providerIds: {'apple.com'},
          isIos: true,
          appleConfigured: false,
        ),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(
        selectAccountDeletionProvider(
          providerIds: {'apple.com', 'google.com'},
          isIos: true,
          appleConfigured: true,
        ),
        AccountDeletionProvider.apple,
      );
    },
  );

  test('unsupported providers fail closed', () {
    expect(
      () => selectAccountDeletionProvider(
        providerIds: {'phone'},
        isIos: false,
        appleConfigured: false,
      ),
      throwsA(isA<AccountDeletionException>()),
    );
  });

  test('disabled environment never contacts the account gateway', () async {
    final gateway = _Gateway();
    await expectLater(
      AccountDeletionService(
        gateway: gateway,
        enabled: false,
      ).deleteCurrentAccount(
        expectedUid: 'user-1',
        requestPassword: () async => 'unused',
      ),
      throwsA(isA<AccountDeletionException>()),
    );
    expect(gateway.calls, isEmpty);
  });

  test(
    'no session, anonymous session and UID mismatch delete nothing',
    () async {
      final cases = <AccountDeletionAccount?>[
        null,
        const AccountDeletionAccount(
          uid: 'user-1',
          email: null,
          anonymous: true,
          providerIds: {},
        ),
        const AccountDeletionAccount(
          uid: 'other',
          email: 'other@example.invalid',
          anonymous: false,
          providerIds: {'google.com'},
        ),
      ];
      for (final account in cases) {
        final gateway = _Gateway(account: account);
        await expectLater(
          runAccountDeletion(
            expectedUid: 'user-1',
            gateway: gateway,
            requestPassword: () async => 'unused',
          ),
          throwsA(isA<AccountDeletionException>()),
        );
        expect(gateway.calls, contains('identity'));
        expect(gateway.calls, isNot(contains('firestore-delete')));
        expect(gateway.calls, isNot(contains('auth-delete')));
      }
    },
  );

  test('Admin is blocked before reauthentication or data deletion', () async {
    final gateway = _Gateway(admin: true);
    await expectLater(
      runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      ),
      throwsA(isA<AccountDeletionException>()),
    );
    expect(gateway.calls, ['identity', 'admin-check']);
  });

  test(
    'reauthentication failure is distinguished before deleting data',
    () async {
      final gateway = _Gateway(failAt: 'reauthenticate');
      await expectLater(
        runAccountDeletion(
          expectedUid: 'user-1',
          gateway: gateway,
          requestPassword: () async => 'unused',
        ),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            'reauthentication_failed',
          ),
        ),
      );
      expect(gateway.calls, ['identity', 'admin-check', 'reauthenticate']);
    },
  );

  test(
    'order is reauth, owned data, local data, Apple revocation, Auth last',
    () async {
      final gateway = _Gateway(appleCode: 'ephemeral-code');
      await runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      );
      expect(gateway.calls, [
        'identity',
        'admin-check',
        'reauthenticate',
        'identity',
        'firestore-delete',
        'local-delete',
        'apple-revoke:ephemeral-code',
        'auth-delete',
      ]);
    },
  );

  test(
    'partial Firestore failure leaves Auth intact and permits retry',
    () async {
      final gateway = _Gateway(failAt: 'firestore-delete');
      await expectLater(
        runAccountDeletion(
          expectedUid: 'user-1',
          gateway: gateway,
          requestPassword: () async => 'unused',
        ),
        throwsStateError,
      );
      expect(gateway.calls, isNot(contains('auth-delete')));
      gateway.failAt = null;
      gateway.calls.clear();
      await runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      );
      expect(gateway.calls, contains('auth-delete'));
    },
  );

  test('local cleanup failure leaves Auth intact', () async {
    final gateway = _Gateway(failAt: 'local-delete');
    await expectLater(
      runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      ),
      throwsStateError,
    );
    expect(gateway.calls, isNot(contains('auth-delete')));
  });

  test(
    'active contact quota stops deletion before local or Auth cleanup',
    () async {
      final gateway = _Gateway(failAt: 'contact-quota-active');
      await expectLater(
        runAccountDeletion(
          expectedUid: 'user-1',
          gateway: gateway,
          requestPassword: () async => 'unused',
        ),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            'contact_quota_active',
          ),
        ),
      );
      expect(gateway.calls, [
        'identity',
        'admin-check',
        'reauthenticate',
        'identity',
        'firestore-delete',
      ]);
      expect(gateway.calls, isNot(contains('local-delete')));
      expect(gateway.calls, isNot(contains('auth-delete')));
    },
  );

  test('registered deletion request stops cleanup and Auth deletion', () async {
    final gateway = _Gateway(failAt: 'deletion-request-registered');
    await expectLater(
      runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      ),
      throwsA(
        isA<AccountDeletionException>()
            .having(
              (error) => error.code,
              'code',
              'deletion_request_registered',
            )
            .having((error) => error.retryAt, 'retryAt', DateTime.utc(2030)),
      ),
    );
    expect(gateway.calls, [
      'identity',
      'admin-check',
      'reauthenticate',
      'identity',
      'firestore-delete',
      'local-delete',
    ]);
    expect(gateway.calls, isNot(contains('auth-delete')));
  });

  test('local cleanup failure keeps the registered request pending', () async {
    final gateway = _Gateway(
      failAt: 'deletion-request-registered',
      failLocalCleanup: true,
    );
    await expectLater(
      runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      ),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          'deletion_request_local_cleanup_failed',
        ),
      ),
    );
    expect(gateway.calls, isNot(contains('auth-delete')));
  });

  test('Apple revocation failure never reports Auth deletion', () async {
    final gateway = _Gateway(
      appleCode: 'ephemeral-code',
      failAt: 'apple-revoke',
    );
    await expectLater(
      runAccountDeletion(
        expectedUid: 'user-1',
        gateway: gateway,
        requestPassword: () async => 'unused',
      ),
      throwsStateError,
    );
    expect(gateway.calls, isNot(contains('auth-delete')));
  });

  test(
    'Auth failure is reported after idempotent cleanup without false success',
    () async {
      final gateway = _Gateway(failAt: 'auth-delete');
      await expectLater(
        runAccountDeletion(
          expectedUid: 'user-1',
          gateway: gateway,
          requestPassword: () async => 'unused',
        ),
        throwsStateError,
      );
      expect(gateway.calls.last, 'auth-delete');
    },
  );
}
