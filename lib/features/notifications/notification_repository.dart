import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/config/firestore_collections.dart';
import '../../core/content/public_content_repository.dart';

class NotificationRecipientException implements Exception {}

/// Public content never stores a recipient. Private content is keyed by UID,
/// independent of email changes. Authorization belongs to Firestore Rules.
class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<List<Map<String, dynamic>>> watch({String? uid}) {
    final public = watchPublicContent(
      FirestoreCollections.notifications,
      firestore: _db,
    ).map((s) => s.docs.map((d) => d.data()).toList());
    if (uid == null) return public;
    final private = _db
        .collection(FirestoreCollections.privateNotifications)
        .where('published', isEqualTo: true)
        .where('targetUid', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
    return mergeNotificationStreams(public, private);
  }

  Future<String> send({
    required String title,
    required String description,
    required String link,
    String? recipientEmail,
  }) async {
    String? uid;
    if (recipientEmail != null) {
      final accounts = await _db
          .collection(FirestoreCollections.users)
          .where('email', isEqualTo: recipientEmail.trim().toLowerCase())
          .limit(2)
          .get(const GetOptions(source: Source.server));
      // Ambiguous/missing accounts must never degrade to a broadcast.
      if (accounts.docs.length != 1) throw NotificationRecipientException();
      uid = accounts.docs.single.id;
      if (uid.isEmpty || uid.length > 128 || uid.contains('/')) {
        throw NotificationRecipientException();
      }
    }
    final payload = notificationContent(
      title: title,
      description: description,
      link: link,
      targetUid: uid,
      timestamp: FieldValue.serverTimestamp(),
    );
    final notification = _db
        .collection(
          uid == null
              ? FirestoreCollections.notifications
              : FirestoreCollections.privateNotifications,
        )
        .doc();
    final queue = _db
        .collection(FirestoreCollections.pushQueue)
        .doc(notification.id);
    final batch = _db.batch();
    batch.set(notification, payload);
    batch.set(queue, {
      ...payload,
      'status': 'queued',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return notification.id;
  }
}

Map<String, dynamic> notificationContent({
  required String title,
  required String description,
  required String link,
  required Object timestamp,
  String? targetUid,
}) => {
  'title': title.trim(),
  'description': description.trim(),
  'link': link.trim(),
  'published': true,
  'updatedAt': timestamp,
  if (targetUid == null) 'targetEmail': '' else 'targetUid': targetUid,
};

Stream<List<Map<String, dynamic>>> mergeNotificationStreams(
  Stream<List<Map<String, dynamic>>> public,
  Stream<List<Map<String, dynamic>>> private,
) => Stream.multi((controller) {
  List<Map<String, dynamic>>? publicItems, privateItems;
  void emit() {
    if (publicItems != null && privateItems != null) {
      controller.add([...publicItems!, ...privateItems!]);
    }
  }

  var completed = 0;
  void done() {
    if (++completed == 2) controller.close();
  }

  final first = public.listen(
    (v) {
      publicItems = v;
      emit();
    },
    onError: controller.addError,
    onDone: done,
  );
  final second = private.listen(
    (v) {
      privateItems = v;
      emit();
    },
    onError: controller.addError,
    onDone: done,
  );
  controller.onCancel = () async {
    await first.cancel();
    await second.cancel();
  };
});
