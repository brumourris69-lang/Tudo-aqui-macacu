import 'secure_backend.dart';

/// Authorship, schema, dates, quotas and deduplication belong to the backend.
Future<void> writeUserOperation(
  String operation,
  Map<String, dynamic> payload,
) async {
  await SecureBackend.invoke('submitUserOperation', {
    'operation': operation,
    'payload': payload,
  });
}
