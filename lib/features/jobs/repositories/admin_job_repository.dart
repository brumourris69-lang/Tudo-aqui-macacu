import 'package:cloud_firestore/cloud_firestore.dart';

const administrativeJobPrivateFields = <String>{
  'contact',
  'phone',
  'whatsapp',
  'link',
  'instagram',
  'maps',
  'mapsUrl',
  'additionalInfo',
};

const _nonPublicJobFields = <String>{
  ...administrativeJobPrivateFields,
  'eventDate',
  'date',
};

/// Removes administrative contact values from the public `jobs` document.
Map<String, dynamic> publicJobPayload(Map<String, dynamic> data) => {
  for (final entry in data.entries)
    if (!_nonPublicJobFields.contains(entry.key)) entry.key: entry.value,
};

Map<String, dynamic> _newPrivateJobPayload(Map<String, dynamic> values) => {
  'schemaVersion': 1,
  'updatedAt': FieldValue.serverTimestamp(),
  for (final field in administrativeJobPrivateFields)
    field: (values[field] ?? '').toString().trim(),
};

Map<String, dynamic> _privateJobPatch(Map<String, dynamic> values) => {
  'schemaVersion': 1,
  'updatedAt': FieldValue.serverTimestamp(),
  for (final field in administrativeJobPrivateFields)
    if (values.containsKey(field))
      field: (values[field] ?? '').toString().trim().isEmpty
          ? FieldValue.delete()
          : (values[field] ?? '').toString().trim(),
};

abstract interface class AdminJobRepository {
  Future<Map<String, dynamic>?> readPrivate(String jobId);

  Future<String> create({
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  });

  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  });

  Future<void> delete(String jobId);
}

/// Persists a vacancy and its administrative contact as one atomic Firestore
/// batch. Security Rules remain the authority for whether the caller is Admin.
class FirestoreAdminJobRepository implements AdminJobRepository {
  FirestoreAdminJobRepository([FirebaseFirestore? firestore])
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  String? _pendingCreateId;

  @override
  Future<Map<String, dynamic>?> readPrivate(String jobId) async {
    final snapshot = await _firestore
        .collection('job_private')
        .doc(jobId)
        .get();
    return snapshot.data();
  }

  @override
  Future<String> create({
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    final jobs = _firestore.collection('jobs');
    final job = _pendingCreateId == null
        ? jobs.doc()
        : jobs.doc(_pendingCreateId);
    _pendingCreateId ??= job.id;
    final private = _firestore.collection('job_private').doc(job.id);
    final batch = _firestore.batch()
      ..set(job, publicJobPayload(publicData))
      ..set(private, _newPrivateJobPayload(privateData));
    await batch.commit();
    _pendingCreateId = null;
    return job.id;
  }

  @override
  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    final batch = _firestore.batch()
      ..update(
        _firestore.collection('jobs').doc(jobId),
        publicJobPayload(publicData),
      )
      ..update(
        _firestore.collection('job_private').doc(jobId),
        _privateJobPatch(privateData),
      );
    await batch.commit();
  }

  @override
  Future<void> delete(String jobId) async {
    final batch = _firestore.batch()
      ..delete(_firestore.collection('jobs').doc(jobId))
      ..delete(_firestore.collection('job_private').doc(jobId));
    await batch.commit();
  }
}
