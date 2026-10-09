import 'package:firebase_auth/firebase_auth.dart';
import 'guest_session.dart';
import '../config/local_search_environment.dart';
import '../content/secure_backend.dart';

bool isRegisteredUser(User? user) => user != null && !user.isAnonymous;

class AppAuth {
  AppAuth._();
  static final guestSession = GuestSession<User>(
    current: () => FirebaseAuth.instance.currentUser,
    anonymousSignIn: () async =>
        (await FirebaseAuth.instance.signInAnonymously()).user,
  );

  static Future<User?> ensureVisitor() async {
    if (!LocalSearchEnvironment.enabled &&
        !SecureBackend.productionAuthorized) {
      return FirebaseAuth.instance.currentUser;
    }
    if (LocalSearchEnvironment.enabled) {
      LocalSearchEnvironment.requireDemo(
        FirebaseAuth.instance.app.options.projectId,
      );
    }
    // Let the SDK restore a persisted account before deciding to create a guest.
    final restored = await FirebaseAuth.instance.authStateChanges().first;
    if (restored != null) return restored;
    return guestSession.ensureVisitor();
  }

  static Future<UserCredential> signInCredential(AuthCredential credential) =>
      guestSession.registeredSignIn(
        () => FirebaseAuth.instance.signInWithCredential(credential),
      );

  // SDK support only: the existing app has no email/password login screen.
  static Future<UserCredential> signInEmail(String email, String password) =>
      guestSession.registeredSignIn(
        () => FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        ),
      );

  static Future<void> logout() async {
    if (LocalSearchEnvironment.enabled || SecureBackend.productionAuthorized) {
      await guestSession.logout(() => FirebaseAuth.instance.signOut());
    } else {
      await FirebaseAuth.instance.signOut();
    }
  }
}
