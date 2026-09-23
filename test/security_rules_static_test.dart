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
        "request.resource.data.diff(resource.data).changedKeys().hasOnly(['displayName', 'email', 'photoUrl', 'updatedAt'])",
      ),
    );
    expect(
      rules,
      contains('request.resource.data.createdAt == resource.data.createdAt'),
    );
    expect(
      rules,
      contains('request.resource.data.email == request.auth.token.email'),
    );
  });

  test('tokens FCM precisam coincidir com o ID do documento', () {
    expect(rules, contains('request.resource.data.token == deviceId'));
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

  test('autorizacao admin aceita custom claims durante migracao', () {
    expect(rules, contains('request.auth.token.admin == true'));
    expect(rules, contains("request.auth.token.role == 'admin'"));
  });
}
