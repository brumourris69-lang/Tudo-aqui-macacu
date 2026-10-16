import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'guest_session.dart';
import '../config/local_firebase_bootstrap.dart';
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
    User? restored;
    try {
      restored = await FirebaseAuth.instance.authStateChanges().first;
    } on FirebaseAuthException catch (error) {
      if (LocalSearchEnvironment.enabled) {
        final current = FirebaseAuth.instance.currentUser;
        debugPrint(
          'Local Auth: restore event failed (${error.code}); '
          'current=${current == null
              ? 'none'
              : current.isAnonymous
              ? 'anonymous'
              : 'registered'}.',
        );
      }
      rethrow;
    }
    if (LocalSearchEnvironment.enabled) {
      debugPrint(
        'Local Auth: restored session='
        '${restored == null
            ? 'none'
            : restored.isAnonymous
            ? 'anonymous'
            : 'registered'}.',
      );
    }
    if (restored != null) {
      if (LocalSearchEnvironment.enabled) {
        try {
          // Validate a restored emulator session before any Firestore read.
          await restored.getIdToken();
        } on FirebaseAuthException catch (error) {
          if (shouldRenewLocalAnonymousSession(
            code: error.code,
            isAnonymous: restored.isAnonymous,
          )) {
            debugPrint(
              'Local Auth: replacing only the stale anonymous emulator session.',
            );
            return renewExpiredLocalVisitor<User>(
              wasAnonymous: restored.isAnonymous,
              signOut: () async {
                await FirebaseAuth.instance.signOut();
                debugPrint('Local Auth: stale anonymous session ended.');
              },
              signInAnonymously: () async {
                debugPrint('Local Auth: requesting a new emulator visitor.');
                final user =
                    (await FirebaseAuth.instance.signInAnonymously()).user;
                debugPrint(
                  user?.isAnonymous == true
                      ? 'Local Auth: new emulator visitor ready.'
                      : 'Local Auth: emulator returned no visitor.',
                );
                return user;
              },
            );
          }
          rethrow;
        }
      }
      return restored;
    }
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
