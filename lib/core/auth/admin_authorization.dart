import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import '../content/secure_backend.dart';
import '../config/local_search_environment.dart';

bool hasAdminClaim(Map<String, dynamic>? claims, {required bool anonymous}) =>
    !anonymous && claims?['admin'] == true;

class AdminClaimState {
  const AdminClaimState({this.uid, this.allowed = false});
  final String? uid;
  final bool allowed;
}

/// UI capability only. Firestore/servers independently authorize every request.
class AdminAuthorization extends ValueNotifier<AdminClaimState> {
  AdminAuthorization({this.watchState, this.checkAdminCallable})
    : super(const AdminClaimState());
  final Stream<Map<String, dynamic>?> Function(String uid)? watchState;
  final Future<dynamic> Function(String operation, Map<String, dynamic> data)?
  checkAdminCallable;
  static final instance = AdminAuthorization();
  StreamSubscription<User?>? _subscription;
  StreamSubscription<Map<String, dynamic>?>? _stateSubscription;
  int _generation = 0;

  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = FirebaseAuth.instance.idTokenChanges().listen(
      (user) => unawaited(updateUser(user)),
      onError: (Object error) {
        _generation++;
        unawaited(_stateSubscription?.cancel());
        value = const AdminClaimState();
      },
    );
    await updateUser(FirebaseAuth.instance.currentUser);
  }

  Future<void> updateUser(User? user, {bool forceRefresh = false}) async {
    final generation = ++_generation;
    value = const AdminClaimState();
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    if (generation != _generation) return;
    if (user == null || user.isAnonymous) return;
    try {
      final result = await user.getIdTokenResult(forceRefresh);
      if (generation != _generation) return;
      {
        if (!hasAdminClaim(result.claims, anonymous: user.isAnonymous)) return;
        final version = result.claims?['adminVersion'];
        if (version is! String || version.isEmpty) return;
        if (LocalSearchEnvironment.enabled ||
            SecureBackend.normalDebugAuthorized) {
          final response = await (checkAdminCallable ?? SecureBackend.invoke)(
            'manageAdminJob',
            const {'operation': 'list', 'pageSize': 1},
          );
          if (generation != _generation) return;
          if (response is Map &&
              response['status'] == 'available' &&
              response['items'] is List) {
            value = AdminClaimState(uid: user.uid, allowed: true);
          }
          return;
        }
        final stream =
            watchState?.call(user.uid) ??
            FirebaseFirestore.instance
                .collection('admin_authorizations')
                .doc(user.uid)
                .snapshots(includeMetadataChanges: true)
                .map(
                  (snapshot) =>
                      snapshot.metadata.isFromCache ? null : snapshot.data(),
                );
        _stateSubscription = stream.listen(
          (state) {
            if (generation != _generation) return;
            value = AdminClaimState(
              uid: user.uid,
              allowed:
                  state?['enabled'] == true &&
                  state?['pending'] == false &&
                  state?['version'] == version,
            );
          },
          onError: (Object error) {
            if (generation == _generation) value = const AdminClaimState();
          },
        );
        return;
      }
    } catch (_) {
      if (generation == _generation) value = const AdminClaimState();
    }
  }

  bool allows(User? user) {
    if (user == null || user.isAnonymous) return false;
    return value.allowed && value.uid == user.uid;
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    super.dispose();
  }
}

class AdminAuthorizationScope extends InheritedNotifier<AdminAuthorization> {
  AdminAuthorizationScope({
    super.key,
    required super.child,
    AdminAuthorization? authorization,
  }) : super(notifier: authorization ?? AdminAuthorization.instance);
  static AdminAuthorization depend(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AdminAuthorizationScope>()
          ?.notifier ??
      AdminAuthorization.instance;
}
