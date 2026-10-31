import 'package:firebase_auth/firebase_auth.dart';

/// Exchanges Google SDK tokens through the existing Firebase Auth client.
/// Injectable authentication keeps token handling testable without OAuth.
Future<T> authenticateGoogleTokens<T>({
  required String? idToken,
  required String? accessToken,
  required Future<T> Function(AuthCredential) authenticate,
}) async {
  final token = idToken?.trim();
  if (token == null || token.isEmpty) {
    throw StateError('Google não retornou o ID token.');
  }
  final credential = GoogleAuthProvider.credential(
    accessToken: accessToken,
    idToken: token,
  );
  return authenticate(credential);
}
