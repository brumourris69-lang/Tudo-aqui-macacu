import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/beta_environment.dart';
import '../../../core/content/spark_admin_content_repository.dart';
import 'admin_job_repository.dart';

/// Firestore-only job administration for the no-Functions Spark Beta.
/// Private contact fields live in `job_private`; public content is projected
/// atomically by SparkAdminContentRepository.
class SparkAdminJobRepository implements AdminJobRepository {
  SparkAdminJobRepository(this._firestore);

  final FirebaseFirestore _firestore;
  String? _reservedId;

  void _requireReady() {
    BetaEnvironment.requireReady();
    BetaEnvironment.requireFirebaseProject(_firestore.app.options.projectId);
  }

  @override
  String reserveCreateId() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return _reservedId ??= List.generate(
      20,
      (_) => alphabet[Random.secure().nextInt(alphabet.length)],
    ).join();
  }

  @override
  Future<AdminJobPage> list({int pageSize = 30, String? cursor}) async {
    _requireReady();
    if (pageSize < 1 || pageSize > 30) {
      throw AdminJobException('invalid-argument');
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection('jobs')
        .orderBy(FieldPath.documentId)
        .limit(pageSize);
    if (cursor != null) query = query.startAfter([cursor]);
    final page = await query.get();
    final items = page.docs
        .map((doc) {
          final data = doc.data();
          return AdminJobSummary(
            id: doc.id,
            title: (data['title'] ?? '').toString(),
            published: data['published'] == true,
            active: data['active'] != false,
          );
        })
        .toList(growable: false);
    return AdminJobPage(
      items: items,
      nextCursor: page.docs.length == pageSize ? page.docs.last.id : null,
    );
  }

  @override
  Future<AdminJobRecord> get(String jobId) async {
    _requireReady();
    final result = await Future.wait([
      _firestore.collection('jobs').doc(jobId).get(),
      _firestore.collection('job_private').doc(jobId).get(),
    ]);
    final public = result[0];
    final private = result[1];
    if (!public.exists) throw AdminJobException('not-found');
    return AdminJobRecord(
      jobId: jobId,
      publicData: public.data() ?? const {},
      privateData: private.data() ?? const {},
    );
  }

  @override
  Future<String> create({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    _requireReady();
    if (_reservedId != jobId) throw AdminJobException('invalid-argument');
    await SparkAdminContentRepository(_firestore).save(
      collection: 'jobs',
      id: jobId,
      data: publicData,
      privateJobData: privateData,
    );
    _reservedId = null;
    return jobId;
  }

  @override
  Future<void> update({
    required String jobId,
    required Map<String, dynamic> publicData,
    required Map<String, dynamic> privateData,
  }) async {
    _requireReady();
    await SparkAdminContentRepository(_firestore).save(
      collection: 'jobs',
      id: jobId,
      data: publicData,
      privateJobData: privateData,
    );
  }

  @override
  Future<void> delete(String jobId) async {
    _requireReady();
    await SparkAdminContentRepository(
      _firestore,
    ).softDelete(collection: 'jobs', id: jobId);
  }
}
