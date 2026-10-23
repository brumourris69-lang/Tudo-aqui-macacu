import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/core/auth/admin_authorization.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

class Token implements IdTokenResult {
  Token(this.claims);
  @override
  final Map<String, dynamic>? claims;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Account implements User {
  Account(
    this.uid, {
    this.email,
    this.isAnonymous = false,
    this.claims = const {},
  });
  @override
  final String uid;
  @override
  final String? email;
  @override
  final bool isAnonymous;
  Map<String, dynamic> claims;
  bool forced = false;
  Future<IdTokenResult>? pending;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    forced = forceRefresh;
    return pending ?? Token(claims);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> updateAndSettle(
  AdminAuthorization state,
  User? user, {
  bool forceRefresh = false,
}) async {
  await state.updateUser(user, forceRefresh: forceRefresh);
  await Future<void>.value();
}

void main() {
  test(
    'searchLocal verifies Admin through the callable, never direct Firestore',
    () async {
      if (!LocalSearchEnvironment.enabled) return;
      final calls = <Map<String, dynamic>>[];
      final state = AdminAuthorization(
        checkAdminCallable: (operation, data) async {
          calls.add({'operation': operation, ...data});
          return {'status': 'available', 'items': <dynamic>[]};
        },
        watchState: (_) =>
            throw StateError('must not read admin_authorizations directly'),
      );
      final user = Account(
        'local-owner',
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      await updateAndSettle(state, user);
      expect(state.allows(user), isTrue);
      expect(calls, [
        {'operation': 'list', 'pageSize': 1},
      ]);
      state.dispose();
    },
    skip: !LocalSearchEnvironment.enabled,
  );

  test(
    'normal Firebase debug checks versioned Admin through manageAdminJob',
    () async {
      SecureBackend.normalDebugOptInOverride = true;
      SecureBackend.normalDebugProjectIdOverride = 'tudo-aqui-macacu';
      final calls = <Map<String, dynamic>>[];
      final state = AdminAuthorization(
        checkAdminCallable: (operation, data) async {
          calls.add({'operation': operation, ...data});
          return {
            'status': 'available',
            'items': <dynamic>[],
            'nextCursor': null,
          };
        },
        watchState: (_) => throw StateError(
          'must not read admin_authorizations in normal debug',
        ),
      );
      final user = Account(
        'owner',
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      await updateAndSettle(state, user);
      expect(state.allows(user), isTrue);
      expect(calls, [
        {'operation': 'list', 'pageSize': 1},
      ]);
      state.dispose();
      SecureBackend.normalDebugOptInOverride = null;
      SecureBackend.normalDebugProjectIdOverride = null;
    },
  );

  test(
    'normal Firebase debug remains denied when callable rejects authorization',
    () async {
      SecureBackend.normalDebugOptInOverride = true;
      SecureBackend.normalDebugProjectIdOverride = 'tudo-aqui-macacu';
      final state = AdminAuthorization(
        checkAdminCallable: (_, _) async => throw StateError('denied'),
        watchState: (_) => throw StateError('must not read Firestore'),
      );
      final user = Account(
        'owner',
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      await updateAndSettle(state, user);
      expect(state.allows(user), isFalse);
      state.dispose();
      SecureBackend.normalDebugOptInOverride = null;
      SecureBackend.normalDebugProjectIdOverride = null;
    },
  );

  test(
    'claim without authorization version cannot unlock Admin or read state',
    () async {
      final state = AdminAuthorization(
        watchState: (_) => throw StateError('must not read'),
      );
      final user = Account('no-version', claims: {'admin': true});
      await state.updateUser(user);
      expect(state.allows(user), isFalse);
      state.dispose();
    },
  );
  testWidgets('claim changes rebuild administrative UI through the scope', (
    tester,
  ) async {
    final user = Account(
      'claim-admin',
      email: 'different@example.invalid',
      claims: {'admin': true, 'adminVersion': 'v1'},
    );
    final session = AdminAuthorization(
      watchState: (_) =>
          Stream.value({'enabled': true, 'pending': false, 'version': 'v1'}),
    );
    await tester.runAsync(() => updateAndSettle(session, user));
    await tester.pumpWidget(
      AdminAuthorizationScope(
        authorization: session,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Text(
              isAdminUser(user, context: context)
                  ? 'Admin permitido'
                  : 'Admin negado',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Admin permitido'), findsOneWidget);
    user.claims = {};
    await tester.runAsync(
      () => updateAndSettle(session, user, forceRefresh: true),
    );
    await tester.pump();
    expect(find.text('Admin negado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => updateAndSettle(session, null));
  }, skip: LocalSearchEnvironment.enabled);
  test(
    'strict UI allows only a verified SDK token boolean claim and excludes visitors',
    () async {
      final state = AdminAuthorization(
        watchState: (_) =>
            Stream.value({'enabled': true, 'pending': false, 'version': 'v1'}),
      );
      final user = Account(
        'owner',
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      expect(state.allows(user), isFalse);
      await updateAndSettle(state, user);
      expect(state.allows(user), isTrue);
      expect(state.allows(Account('other')), isFalse);
      expect(state.allows(null), isFalse);
      final visitor = Account(
        'visitor',
        isAnonymous: true,
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      await updateAndSettle(state, visitor);
      expect(state.allows(visitor), isFalse);
      state.dispose();
    },
    skip: LocalSearchEnvironment.enabled,
  );
  test(
    'legacy email, role profile/claim and string admin do not grant local Admin',
    () async {
      final state = AdminAuthorization(
        watchState: (_) =>
            Stream.value({'enabled': true, 'pending': false, 'version': 'v1'}),
      );
      for (final claims in <Map<String, dynamic>>[
        {},
        {'role': 'admin'},
        {'admin': 'true'},
      ]) {
        final user = Account(
          'legacy',
          email: 'legacy-admin@example.com',
          claims: claims,
        );
        await updateAndSettle(state, user);
        expect(state.allows(user), isFalse);
        expect(state.allows(user), isFalse);
      }
      state.dispose();
    },
    skip: LocalSearchEnvironment.enabled,
  );
  test(
    'forced refresh updates grants and revocation; stale response cannot cross account/logout',
    () async {
      final state = AdminAuthorization(
        watchState: (_) =>
            Stream.value({'enabled': true, 'pending': false, 'version': 'v1'}),
      );
      final user = Account(
        'owner',
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      await updateAndSettle(state, user, forceRefresh: true);
      expect(user.forced, isTrue);
      expect(state.allows(user), isTrue);
      user.claims = {};
      await updateAndSettle(state, user, forceRefresh: true);
      expect(state.allows(user), isFalse);
      final delayed = Completer<IdTokenResult>();
      user.pending = delayed.future;
      final stale = state.updateUser(user);
      await updateAndSettle(state, null);
      delayed.complete(Token({'admin': true, 'adminVersion': 'v1'}));
      await stale;
      expect(state.allows(user), isFalse);
      expect(state.value.uid, isNull);
      state.dispose();
    },
    skip: LocalSearchEnvironment.enabled,
  );
  test(
    'current state disables UI on revoke, stale version, missing state and communication error',
    () async {
      final changes = StreamController<Map<String, dynamic>?>();
      final state = AdminAuthorization(watchState: (_) => changes.stream);
      final user = Account(
        'admin',
        claims: {'admin': true, 'adminVersion': 'v1'},
      );
      await updateAndSettle(state, user);
      expect(state.allows(user), isFalse);
      changes.add({'enabled': true, 'pending': false, 'version': 'v1'});
      await Future<void>.delayed(Duration.zero);
      expect(state.allows(user), isTrue);
      for (final value in <Map<String, dynamic>?>[
        {'enabled': false, 'pending': false, 'version': 'v1'},
        {'enabled': true, 'pending': false, 'version': 'v2'},
        {'enabled': true, 'pending': true, 'version': 'v1'},
        null,
      ]) {
        changes.add(value);
        await Future<void>.delayed(Duration.zero);
        expect(state.allows(user), isFalse);
      }
      changes.addError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(state.allows(user), isFalse);
      await updateAndSettle(state, null);
      state.dispose();
      await changes.close();
    },
    skip: LocalSearchEnvironment.enabled,
  );
}
