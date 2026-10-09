import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unified Rules preserve administrative revocation and private notifications while hardening public visibility',
    () {
      final production = File(
        'firestore.rules',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final staged = File(
        'firestore.claims-local.rules',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      String privateRules(String rules) => rules.substring(
        rules.indexOf('    match /private_notifications/'),
        rules.indexOf('    match /push_queue/'),
      );
      expect(staged, production);
      expect(privateRules(staged), privateRules(production));
      expect(
        staged,
        contains('state.version == request.auth.token.adminVersion'),
      );
      expect(staged, contains('visibleDocument(collection)'));
      expect(
        staged,
        contains('allow list: if publicCollection(collection) && admin();'),
      );
      expect(
        staged,
        contains("request.auth.token.get('admin', false) == true"),
      );
      expect(staged, isNot(contains("token.role == 'admin'")));
      expect(
        staged,
        isNot(contains("token.email == 'legacy-admin@example.com'")),
      );
      expect(staged, contains('match /private_notifications/'));
      expect(
        File('firebase.json').readAsStringSync(),
        contains('"rules": "firestore.rules"'),
      );
      expect(
        File('firebase.search-emulator.json').readAsStringSync(),
        contains('"rules": "firestore.rules"'),
      );
    },
  );
}
