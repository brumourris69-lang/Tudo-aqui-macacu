import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/config/firestore_collections.dart';

void main() {
  test('constantes preservam nomes atuais das collections principais', () {
    expect(FirestoreCollections.users, 'users');
    expect(FirestoreCollections.establishments, 'establishments');
    expect(FirestoreCollections.utilities, 'utilities');
    expect(FirestoreCollections.events, 'events');
    expect(FirestoreCollections.news, 'news');
    expect(FirestoreCollections.jobs, 'jobs');
    expect(FirestoreCollections.routes, 'routes');
    expect(FirestoreCollections.metrics, 'metrics');
    expect(FirestoreCollections.adminAuditLogs, 'admin_audit_logs');
    expect(FirestoreCollections.notifications, 'notifications');
    expect(FirestoreCollections.pushQueue, 'push_queue');
  });

  test('subcollections preservam nomes atuais', () {
    expect(FirestoreCollections.favorites, 'favorites');
    expect(FirestoreCollections.devices, 'devices');
    expect(FirestoreCollections.votes, 'votes');
  });
}
