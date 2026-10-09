import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firestore.rules').readAsStringSync();
  });

  test('perfil protege role, createdAt e email do Auth', () {
    expect(rules, contains("request.resource.data.role == 'user'"));
    expect(
      rules,
      contains(
        'request.resource.data.diff(resource.data).affectedKeys().hasOnly(',
      ),
    );
    expect(
      rules,
      contains(
        "request.resource.data.createdAt == resource.data.get('createdAt', request.time)",
      ),
    );
    expect(
      rules,
      contains(
        "request.resource.data.email == request.auth.token.get('email', '')",
      ),
    );
  });

  test('tokens FCM precisam coincidir com o ID do documento', () {
    final deviceRules = rules.substring(
      rules.indexOf('match /devices/'),
      rules.indexOf('match /metrics/'),
    );
    expect(deviceRules, contains('allow create, update: if false;'));
    final backend = File('functions/user_operations.js').readAsStringSync();
    expect(backend, contains("user.collection('devices').doc(p.token)"));
    expect(
      backend,
      contains("data = { ...p, active: true, updatedAt: stamp }"),
    );
  });

  test('fila de push e audit logs sao restritos e validados', () {
    expect(rules, contains("match /push_queue/{notificationId}"));
    expect(rules, contains("request.resource.data.status == 'queued'"));
    expect(rules, contains("match /admin_audit_logs/{logId}"));
    expect(
      rules,
      contains('request.resource.data.adminUid == request.auth.uid'),
    );
    expect(rules, contains('allow update, delete: if false'));
  });

  test(
    'autorizacao admin exige claim e estado atual versionado, sem email ou role',
    () {
      expect(rules, contains("request.auth.token.get('admin', false) == true"));
      expect(
        rules,
        contains('state.version == request.auth.token.adminVersion'),
      );
      expect(
        rules,
        contains('state.enabled == true && state.pending == false'),
      );
      expect(rules, isNot(contains("request.auth.token.role == 'admin'")));
      expect(rules, isNot(contains('legacy-admin@example.com')));
    },
  );
}
