import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';

import '../../features/events/services/event_reminder_service.dart';
import '../config/beta_environment.dart';
import '../config/local_search_environment.dart';
import '../config/spark_local_environment.dart';
import '../config/spark_public_catalog_environment.dart';
import '../config/staging_environment.dart';
import 'admin_authorization.dart';
import 'google_sign_in_configuration.dart';

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.code, {this.retryAt});

  final String code;
  final DateTime? retryAt;

  @override
  String toString() => 'AccountDeletionException($code)';
}

class AccountDeletionReauthentication {
  const AccountDeletionReauthentication({this.appleAuthorizationCode});

  final String? appleAuthorizationCode;
}

class AccountDeletionAccount {
  const AccountDeletionAccount({
    required this.uid,
    required this.email,
    required this.anonymous,
    required this.providerIds,
  });

  final String uid;
  final String? email;
  final bool anonymous;
  final Set<String> providerIds;
}

enum AccountDeletionProvider { apple, password, google }

AccountDeletionProvider selectAccountDeletionProvider({
  required Set<String> providerIds,
  required bool isIos,
  required bool appleConfigured,
}) {
  if (providerIds.contains('apple.com')) {
    if (!isIos || !appleConfigured) {
      throw const AccountDeletionException('apple_provider_not_configured');
    }
    return AccountDeletionProvider.apple;
  }
  if (providerIds.contains(EmailAuthProvider.PROVIDER_ID)) {
    return AccountDeletionProvider.password;
  }
  if (providerIds.contains(GoogleAuthProvider.PROVIDER_ID)) {
    return AccountDeletionProvider.google;
  }
  throw const AccountDeletionException('provider_not_supported');
}

abstract interface class AccountDeletionGateway {
  Future<AccountDeletionAccount?> currentAccount();
  Future<bool> isAdministrator(String uid);
  Future<AccountDeletionReauthentication> reauthenticate(
    AccountDeletionAccount account, {
    required Future<String?> Function() requestPassword,
  });

  Future<void> deletePersonalData(String uid);
  Future<void> clearLocalData(String uid);
  Future<void> revokeAppleToken(String authorizationCode);
  Future<void> deleteAuthAccount(String uid);
}

/// Enforces identity checks and a retryable, data-first deletion sequence.
Future<void> runAccountDeletion({
  required String expectedUid,
  required AccountDeletionGateway gateway,
  required Future<String?> Function() requestPassword,
}) async {
  late final AccountDeletionAccount? account;
  try {
    account = await gateway.currentAccount();
  } on AccountDeletionException {
    rethrow;
  } catch (_) {
    throw const AccountDeletionException('identity_check_failed');
  }
  if (account == null || account.anonymous) {
    throw const AccountDeletionException('no_registered_session');
  }
  if (account.uid != expectedUid) {
    throw const AccountDeletionException('account_changed');
  }
  late final bool isAdmin;
  try {
    isAdmin = await gateway.isAdministrator(expectedUid);
  } on AccountDeletionException {
    rethrow;
  } catch (_) {
    throw const AccountDeletionException('identity_check_failed');
  }
  if (isAdmin) {
    throw const AccountDeletionException('admin_account');
  }

  late final AccountDeletionReauthentication reauthentication;
  try {
    reauthentication = await gateway.reauthenticate(
      account,
      requestPassword: requestPassword,
    );
  } on AccountDeletionException {
    rethrow;
  } catch (_) {
    throw const AccountDeletionException('reauthentication_failed');
  }
  late final AccountDeletionAccount? afterReauthentication;
  try {
    afterReauthentication = await gateway.currentAccount();
  } on AccountDeletionException {
    rethrow;
  } catch (_) {
    throw const AccountDeletionException('identity_check_failed');
  }
  if (afterReauthentication == null ||
      afterReauthentication.anonymous ||
      afterReauthentication.uid != expectedUid) {
    throw const AccountDeletionException('account_changed');
  }

  // Each operation is idempotent. Auth is deleted last so a failed cleanup
  // leaves a signed-in account that can retry, without a false success state.
  try {
    await gateway.deletePersonalData(expectedUid);
  } on AccountDeletionException catch (error) {
    if (error.code != 'deletion_request_registered') rethrow;
    try {
      await gateway.clearLocalData(expectedUid);
    } catch (_) {
      throw AccountDeletionException(
        'deletion_request_local_cleanup_failed',
        retryAt: error.retryAt,
      );
    }
    rethrow;
  }
  await gateway.clearLocalData(expectedUid);
  final appleCode = reauthentication.appleAuthorizationCode?.trim();
  if (appleCode != null && appleCode.isNotEmpty) {
    await gateway.revokeAppleToken(appleCode);
  }
  await gateway.deleteAuthAccount(expectedUid);
}

class FirebaseAccountDeletionGateway implements AccountDeletionGateway {
  FirebaseAccountDeletionGateway({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    EventReminderService? reminders,
    GoogleSignIn Function()? googleSignInFactory,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _reminders = reminders ?? EventReminderService.instance,
       _googleSignInFactory = googleSignInFactory ?? _defaultGoogleSignIn;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final EventReminderService _reminders;
  final GoogleSignIn Function() _googleSignInFactory;

  static GoogleSignIn _defaultGoogleSignIn() => GoogleSignIn(
    clientId: googleSignInNativeClientId(
      betaVariant: BetaEnvironment.enabled,
      ios: defaultTargetPlatform == TargetPlatform.iOS,
      betaIosClientId: BetaEnvironment.iosGoogleClientId,
    ),
    serverClientId: googleSignInServerClientId(
      betaVariant: BetaEnvironment.enabled,
      betaClientId: BetaEnvironment.googleWebClientId,
    ),
  );

  static bool supportsCurrentBuild({
    required bool betaBuild,
    required bool sparkDistributionBuild,
    required bool sparkLocalBuild,
    required bool localSearchBuild,
    required bool stagingBuild,
  }) =>
      betaBuild != sparkDistributionBuild &&
      !sparkLocalBuild &&
      !localSearchBuild &&
      !stagingBuild;

  static bool matchesFirebaseIdentity({
    required String authProjectId,
    required String firestoreProjectId,
    required String authAppId,
    required String firestoreAppId,
  }) =>
      authProjectId.isNotEmpty &&
      authProjectId == firestoreProjectId &&
      authAppId.isNotEmpty &&
      authAppId == firestoreAppId;

  static bool get enabledForCurrentEnvironment => supportsCurrentBuild(
    betaBuild: BetaEnvironment.enabled,
    sparkDistributionBuild: SparkPublicCatalogEnvironment.enabled,
    sparkLocalBuild: SparkLocalEnvironment.enabled,
    localSearchBuild: LocalSearchEnvironment.enabled,
    stagingBuild: StagingEnvironment.enabled,
  );

  void _requireEnvironment() {
    if (!supportsCurrentBuild(
      betaBuild: BetaEnvironment.enabled,
      sparkDistributionBuild: SparkPublicCatalogEnvironment.enabled,
      sparkLocalBuild: SparkLocalEnvironment.enabled,
      localSearchBuild: LocalSearchEnvironment.enabled,
      stagingBuild: StagingEnvironment.enabled,
    )) {
      throw const AccountDeletionException('unsupported_environment');
    }
    final authProject = _auth.app.options.projectId;
    final firestoreProject = _firestore.app.options.projectId;
    if (!matchesFirebaseIdentity(
      authProjectId: authProject,
      firestoreProjectId: firestoreProject,
      authAppId: _auth.app.options.appId,
      firestoreAppId: _firestore.app.options.appId,
    )) {
      throw const AccountDeletionException('identity_check_failed');
    }
    if (BetaEnvironment.enabled) {
      BetaEnvironment.requireReady();
      BetaEnvironment.requireFirebaseProject(authProject);
      BetaEnvironment.requireFirebaseProject(firestoreProject);
      return;
    }
    SparkPublicCatalogEnvironment.requireReady(actualProjectId: authProject);
    SparkPublicCatalogEnvironment.requireReady(
      actualProjectId: firestoreProject,
    );
  }

  User _requireUid(String uid) {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const AccountDeletionException('no_registered_session');
    }
    if (user.uid != uid) {
      throw const AccountDeletionException('account_changed');
    }
    return user;
  }

  @override
  Future<AccountDeletionAccount?> currentAccount() async {
    _requireEnvironment();
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    final current = _auth.currentUser;
    if (current == null) return null;
    return AccountDeletionAccount(
      uid: current.uid,
      email: current.email,
      anonymous: current.isAnonymous,
      providerIds: current.providerData.map((item) => item.providerId).toSet(),
    );
  }

  @override
  Future<bool> isAdministrator(String uid) async {
    _requireEnvironment();
    final user = _requireUid(uid);
    final token = await user.getIdTokenResult(true);
    // Any Admin claim, including a stale or revoked one, requires out-of-band
    // deprovisioning. Never let account deletion remove its own authorization.
    return token.claims?['admin'] == true ||
        AdminAuthorization.instance.allows(user);
  }

  @override
  Future<AccountDeletionReauthentication> reauthenticate(
    AccountDeletionAccount account, {
    required Future<String?> Function() requestPassword,
  }) async {
    _requireEnvironment();
    final user = _requireUid(account.uid);
    final providers = account.providerIds;
    final method = selectAccountDeletionProvider(
      providerIds: providers,
      isIos: defaultTargetPlatform == TargetPlatform.iOS,
      appleConfigured:
          BetaEnvironment.enabled && BetaEnvironment.iosAppleSignInEnabled,
    );

    if (method == AccountDeletionProvider.apple) {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final credential = await user.reauthenticateWithProvider(provider);
      if (_auth.currentUser?.uid != account.uid) {
        throw const AccountDeletionException('account_changed');
      }
      final authorizationCode =
          credential.additionalUserInfo?.authorizationCode;
      if (authorizationCode == null || authorizationCode.trim().isEmpty) {
        throw const AccountDeletionException('apple_revocation_code_missing');
      }
      return AccountDeletionReauthentication(
        appleAuthorizationCode: authorizationCode,
      );
    }

    if (method == AccountDeletionProvider.password) {
      final password = await requestPassword();
      if (password == null || password.isEmpty) {
        throw const AccountDeletionException('reauthentication_cancelled');
      }
      final email = account.email?.trim();
      if (email == null || email.isEmpty) {
        throw const AccountDeletionException('email_unavailable');
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
    } else if (method == AccountDeletionProvider.google) {
      final account = await _googleSignInFactory().signIn();
      if (account == null) {
        throw const AccountDeletionException('reauthentication_cancelled');
      }
      final tokens = await account.authentication;
      final idToken = tokens.idToken?.trim();
      if (idToken == null || idToken.isEmpty) {
        throw const AccountDeletionException('google_token_unavailable');
      }
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(
          idToken: idToken,
          accessToken: tokens.accessToken,
        ),
      );
    }
    if (_auth.currentUser?.uid != account.uid) {
      throw const AccountDeletionException('account_changed');
    }
    return const AccountDeletionReauthentication();
  }

  @override
  Future<void> deletePersonalData(String uid) async {
    _requireEnvironment();
    final profile = await _firestore.collection('users').doc(uid).get();
    if (profile.exists && profile.data()?['role'] != 'user') {
      throw const AccountDeletionException('protected_profile');
    }

    final userRef = _firestore.collection('users').doc(uid);
    final quota = userRef.collection('contact_message_limits').doc('current');
    final quotaSnapshot = await quota.get();
    if (quotaSnapshot.exists) {
      final quotaData = quotaSnapshot.data();
      final periodStartedAt = quotaData?['periodStartedAt'];
      if (quotaData?['uid'] != uid || periodStartedAt is! Timestamp) {
        throw const AccountDeletionException('contact_quota_state_invalid');
      }

      _requireUid(uid);
      try {
        // Firestore Rules use request.time, so the server remains the authority
        // for the 24-hour boundary. Do this before other cleanup so an active
        // quota cannot leave a partially deleted account.
        await quota.delete();
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          final retryAfter = Timestamp(
            periodStartedAt.seconds + const Duration(hours: 24).inSeconds,
            periodStartedAt.nanoseconds,
          );
          await _registerDeletionRequest(uid, retryAfter: retryAfter);
        }
        rethrow;
      }
    }

    await _deletePages(
      () => userRef.collection('favorites').limit(100),
      uid,
      pathOwned: true,
    );
    await _deletePages(
      () => userRef.collection('devices').limit(100),
      uid,
      pathOwned: true,
    );
    await _deletePages(
      () => _firestore
          .collectionGroup('votes')
          .where('uid', isEqualTo: uid)
          .limit(100),
      uid,
      ownerFields: const {'uid'},
    );
    await _deleteLegacyVotesForPublishedPolls(uid);
    for (final collection in const [
      'contact_messages',
      'business_proposals',
      'reviews',
      'metrics',
    ]) {
      for (final ownerField in const ['uid', 'userId']) {
        await _deletePages(
          () => _firestore
              .collection(collection)
              .where(ownerField, isEqualTo: uid)
              .limit(100),
          uid,
          ownerFields: const {'uid', 'userId'},
        );
      }
    }
    for (final privateCollection in const [
      'private_notifications',
      'push_queue',
    ]) {
      await _deletePages(
        () => _firestore
            .collection(privateCollection)
            .where('targetUid', isEqualTo: uid)
            .limit(100),
        uid,
        ownerFields: const {'targetUid'},
      );
    }

    // Older callable notifications were addressed by email before stable UID
    // delivery was introduced. The Rules compare this query to the current
    // Firebase Auth email and reject records whose targetUid names another
    // account. Omitting a targetUid filter also finds legacy documents where
    // that field was never written. Records for a previous email remain an
    // operator-only historical cleanup case.
    final accountEmail = _auth.currentUser?.email?.trim();
    if (accountEmail != null && accountEmail.isNotEmpty) {
      for (final collection in const ['notifications', 'push_queue']) {
        await _deletePages(
          () => _firestore
              .collection(collection)
              .where('targetEmail', isEqualTo: accountEmail)
              .limit(100),
          uid,
          ownerValues: {'targetEmail': accountEmail, 'targetUid': ''},
        );
      }
    }
  }

  Future<void> _deleteLegacyVotesForPublishedPolls(String uid) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      _requireUid(uid);
      var query = _firestore
          .collection('beta_public_catalog')
          .doc('polls')
          .collection('items')
          .where('visibility', isEqualTo: 'public')
          .limit(40);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get();
      if (page.docs.isEmpty) return;
      final batch = _firestore.batch();
      var deletes = 0;
      for (final poll in page.docs) {
        _requireUid(uid);
        final vote = await _firestore
            .collection('polls')
            .doc(poll.id)
            .collection('votes')
            .doc(uid)
            .get();
        if (!vote.exists) continue;
        final voteUid = vote.data()?['uid'];
        if (voteUid != null && voteUid != uid) {
          throw const AccountDeletionException('owned_data_mismatch');
        }
        batch.delete(vote.reference);
        deletes++;
      }
      if (deletes > 0) {
        _requireUid(uid);
        await batch.commit();
      }
      if (page.docs.length < 40) return;
      cursor = page.docs.last;
    }
  }

  Future<Never> _registerDeletionRequest(
    String uid, {
    required Timestamp retryAfter,
  }) async {
    _requireUid(uid);
    final request = _firestore.collection('account_deletion_requests').doc(uid);

    Future<Timestamp?> existingRequestRetryAfter() async {
      final snapshot = await request.get();
      if (!snapshot.exists) return null;
      final data = snapshot.data();
      final storedRetryAt = data?['retryAfter'];
      if (data?['uid'] != uid ||
          data?['status'] != 'pending' ||
          storedRetryAt is! Timestamp) {
        throw const AccountDeletionException('deletion_request_state_invalid');
      }
      return storedRetryAt;
    }

    final existingRetryAfter = await existingRequestRetryAfter();
    if (existingRetryAfter != null) {
      throw AccountDeletionException(
        'deletion_request_registered',
        retryAt: existingRetryAfter.toDate(),
      );
    }

    try {
      await request.set({
        'uid': uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'retryAfter': retryAfter,
        'status': 'pending',
      });
    } on FirebaseException {
      // A concurrent retry may have created the same UID-keyed request.
      // Treat only a valid pending document as the same successful request.
      final concurrentRetryAfter = await existingRequestRetryAfter();
      if (concurrentRetryAfter != null) {
        throw AccountDeletionException(
          'deletion_request_registered',
          retryAt: concurrentRetryAfter.toDate(),
        );
      }
      rethrow;
    }

    throw AccountDeletionException(
      'deletion_request_registered',
      retryAt: retryAfter.toDate(),
    );
  }

  Future<void> _deletePages(
    Query<Map<String, dynamic>> Function() queryFactory,
    String uid, {
    bool pathOwned = false,
    Set<String> ownerFields = const {'uid'},
    Map<String, Object?>? ownerValues,
  }) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      _requireUid(uid);
      var query = queryFactory();
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get();
      if (page.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final document in page.docs) {
        final data = document.data();
        final isOwned = pathOwned
            ? document.reference.path.startsWith('users/$uid/')
            : ownerValues != null
            ? ownerValues.entries.any(
                    (entry) => data[entry.key] == entry.value,
                  ) &&
                  ownerValues.entries.every(
                    (entry) => entry.key == 'targetUid' && entry.value == ''
                        ? !data.containsKey(entry.key) || data[entry.key] == ''
                        : data[entry.key] == entry.value,
                  )
            : ownerFields.any((field) => data[field] == uid) &&
                  ownerFields.every(
                    (field) => !data.containsKey(field) || data[field] == uid,
                  );
        if (!isOwned) {
          throw const AccountDeletionException('owned_data_mismatch');
        }
        batch.delete(document.reference);
      }
      _requireUid(uid);
      await batch.commit();
      if (page.docs.length < 100) return;
      cursor = page.docs.last;
    }
  }

  @override
  Future<void> clearLocalData(String uid) async {
    _requireEnvironment();
    _requireUid(uid);
    await _reminders.clearUserForAccountDeletion(uid);
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {
    _requireEnvironment();
    await _auth.revokeTokenWithAuthorizationCode(authorizationCode);
  }

  @override
  Future<void> deleteAuthAccount(String uid) async {
    _requireEnvironment();
    final user = _requireUid(uid);

    final userRef = _firestore.collection('users').doc(uid);
    final profile = await userRef.get();
    if (profile.exists && profile.data()?['role'] != 'user') {
      throw const AccountDeletionException('protected_profile');
    }
    final quota = userRef.collection('contact_message_limits').doc('current');
    final quotaSnapshot = await quota.get();
    if (quotaSnapshot.exists) {
      final periodStartedAt = quotaSnapshot.data()?['periodStartedAt'];
      if (periodStartedAt is! Timestamp) {
        throw const AccountDeletionException('contact_quota_state_invalid');
      }
      throw AccountDeletionException(
        'contact_quota_active',
        retryAt: periodStartedAt.toDate().add(const Duration(hours: 24)),
      );
    }

    final requestRef = _firestore
        .collection('account_deletion_requests')
        .doc(uid);
    final requestSnapshot = await requestRef.get();
    final batch = _firestore.batch();
    if (profile.exists) batch.delete(userRef);
    if (requestSnapshot.exists) {
      final requestData = requestSnapshot.data();
      if (requestData?['uid'] != uid || requestData?['status'] != 'pending') {
        throw const AccountDeletionException('deletion_request_state_invalid');
      }
      batch.delete(requestRef);
    }
    if (profile.exists || requestSnapshot.exists) await batch.commit();

    await user.delete();
    await AdminAuthorization.instance.updateUser(null);
  }
}

class AccountDeletionService {
  AccountDeletionService({AccountDeletionGateway? gateway, bool? enabled})
    : _gateway = gateway ?? FirebaseAccountDeletionGateway(),
      _enabled =
          enabled ??
          FirebaseAccountDeletionGateway.enabledForCurrentEnvironment;

  static final instance = AccountDeletionService();

  final AccountDeletionGateway _gateway;
  final bool _enabled;

  Future<void> deleteCurrentAccount({
    required String expectedUid,
    required Future<String?> Function() requestPassword,
  }) async {
    if (!_enabled) {
      throw const AccountDeletionException('unsupported_environment');
    }
    await runAccountDeletion(
      expectedUid: expectedUid,
      gateway: _gateway,
      requestPassword: requestPassword,
    );
  }
}
