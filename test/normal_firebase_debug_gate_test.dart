import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';
import 'package:tudo_aqui_macacu/core/config/local_search_environment.dart';
import 'package:tudo_aqui_macacu/features/auth/local_session_recovery.dart';
import 'package:tudo_aqui_macacu/features/jobs/repositories/admin_job_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SecureBackend.normalDebugOptInOverride = null;
    SecureBackend.normalDebugProjectIdOverride = null;
    SecureBackend.normalDebugInvokerOverride = null;
  });

  test(
    'debug Firebase gate requires opt-in, exact project, and debug mode',
    () {
      bool allowed({
        bool debugBuild = true,
        bool optIn = true,
        bool localSearch = false,
        bool staging = false,
        String projectId = 'tudo-aqui-macacu',
      }) => isNormalFirebaseDebugAuthorized(
        debugBuild: debugBuild,
        optIn: optIn,
        localSearch: localSearch,
        staging: staging,
        projectId: projectId,
      );

      expect(allowed(), isTrue);
      expect(allowed(debugBuild: false), isFalse);
      expect(allowed(optIn: false), isFalse);
      expect(allowed(localSearch: true), isFalse);
      expect(allowed(staging: true), isFalse);
      expect(allowed(projectId: 'demo-universal-search'), isFalse);
      expect(allowed(projectId: 'another-project'), isFalse);
    },
  );

  testWidgets(
    'local session recovery controls stay unavailable outside searchLocal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionRecoveryView(
            failureKind: LocalSessionFailureKind.inconclusive,
            onValidateCurrentSession: () async {},
            onSwitchAccount: (_, _) async {},
            onContinueAsVisitor: () async {},
            onReady: (_) => const Text('Protected app'),
          ),
        ),
      );

      expect(find.text('Recuperação local indisponível.'), findsOneWidget);
      expect(find.byKey(const Key('retry-session')), findsNothing);
      expect(find.byKey(const Key('switch-account')), findsNothing);
      expect(find.byKey(const Key('continue-visitor')), findsNothing);
    },
    skip: LocalSearchEnvironment.enabled,
  );

  test(
    'explicit debug opt-in opens only the safe callable allowlist',
    () async {
      SecureBackend.normalDebugOptInOverride = true;
      SecureBackend.normalDebugProjectIdOverride = 'tudo-aqui-macacu';
      final calls = <String>[];
      SecureBackend.normalDebugInvokerOverride = (name, data) async {
        calls.add(name);
        return {'accepted': true, 'data': data};
      };

      for (final operation in [
        'listPublicContent',
        'getPublicContentDetail',
        'manageAdminJob',
      ]) {
        expect(await SecureBackend.invoke(operation, {'operation': 'probe'}), {
          'accepted': true,
          'data': {'operation': 'probe'},
        });
      }
      await expectLater(
        SecureBackend.invoke('getPublicJob', {'id': 'job-1'}),
        throwsArgumentError,
      );
      await expectLater(
        SecureBackend.invoke('submitUserOperation', const {}),
        throwsStateError,
      );
      expect(calls, [
        'listPublicContent',
        'getPublicContentDetail',
        'manageAdminJob',
      ]);
      expect(SecureBackend.productionAuthorized, isFalse);
    },
  );

  test(
    'wrong project and missing opt-in fail before callable invocation',
    () async {
      var calls = 0;
      SecureBackend.normalDebugOptInOverride = true;
      SecureBackend.normalDebugProjectIdOverride = 'demo-universal-search';
      SecureBackend.normalDebugInvokerOverride = (_, _) async {
        calls++;
        return null;
      };

      await expectLater(
        SecureBackend.invoke('listPublicContent', const {}),
        throwsStateError,
      );
      expect(calls, 0);

      SecureBackend.normalDebugOptInOverride = false;
      SecureBackend.normalDebugProjectIdOverride = 'tudo-aqui-macacu';
      await expectLater(
        SecureBackend.invoke('manageAdminJob', {'operation': 'list'}),
        throwsArgumentError,
      );
      expect(calls, 0);
    },
  );

  test(
    'admin jobs repository uses the opt-in manageAdminJob callable',
    () async {
      SecureBackend.normalDebugOptInOverride = true;
      SecureBackend.normalDebugProjectIdOverride = 'tudo-aqui-macacu';
      var invoked = false;
      SecureBackend.normalDebugInvokerOverride = (name, data) async {
        invoked = true;
        expect(name, 'manageAdminJob');
        expect(data, {'operation': 'list', 'pageSize': 30});
        return {'status': 'available', 'items': [], 'nextCursor': null};
      };

      final page = await CallableAdminJobRepository().list();

      expect(invoked, isTrue);
      expect(page.items, isEmpty);
      expect(SecureBackend.productionAuthorized, isFalse);
    },
  );
}
