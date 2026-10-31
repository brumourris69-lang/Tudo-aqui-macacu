import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/beta_environment.dart';

/// Direct Firestore writer used by the Spark Beta administrative editors.
///
/// Authorization is enforced by `firestore.beta.rules`: the caller must have
/// a current, out-of-band provisioned Admin claim and authorization record.
/// Canonical content and its public allowlisted projection are changed in one
/// transaction so drafts and hidden content never remain publicly readable.
class SparkAdminContentRepository {
  SparkAdminContentRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const editableCollections = <String>{
    'establishments',
    'routes',
    'events',
    'utilities',
    'ads',
    'offers',
    'coupons',
    'alerts',
    'polls',
    'jobs',
    'news',
    'links',
    'health',
    'transport',
    'trash_collection',
    'useful_phones',
    'pharmacy_duties',
    'emergency_contacts',
    'resolver_subjects',
    'public_places',
  };

  static const _publicFields = <String>{
    'name',
    'title',
    'category',
    'subcategory',
    'description',
    'shortDescription',
    'location',
    'address',
    'iconKey',
    'imageUrl',
    'logoUrl',
    'maps',
    'mapsUrl',
    'phone',
    'whatsapp',
    'instagram',
    'type',
    'employmentType',
    'company',
    'eventDate',
    'endDate',
    'date',
    'startsAt',
    'startTime',
    'endTime',
    'organizer',
    'registrationUrl',
    'contactUrl',
    'link',
    'destinationType',
    'destination',
    'promotionTitle',
    'promotionDescription',
    'hours',
    'additionalInfo',
    'galleryUrls',
    'videoUrls',
    'services',
    'products',
    'artwork',
    'order',
    'featured',
    'open',
    'options',
  };

  static Map<String, dynamic> publicProjection(Map<String, dynamic> source) {
    final projection = <String, dynamic>{
      for (final entry in source.entries)
        if (_publicFields.contains(entry.key) && entry.value != null)
          entry.key: entry.value,
    };
    final title = projection['name'] ?? projection['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('Conteúdo público precisa de um título.');
    }
    if (projection.length > 44) {
      throw const FormatException(
        'Conteúdo público excede o limite de campos.',
      );
    }
    return projection;
  }

  static bool isPermanentlyDeleted(Map<String, dynamic>? source) =>
      source?['deleted'] == true ||
      (source?['deletedAt'] != null && source?['deletedAt'] is! FieldValue);

  void _requireTarget(String collection, String id) {
    BetaEnvironment.requireReady();
    BetaEnvironment.requireFirebaseProject(_firestore.app.options.projectId);
    if (!editableCollections.contains(collection) ||
        id.trim().isEmpty ||
        id.contains('/') ||
        id == '.' ||
        id == '..') {
      throw ArgumentError('Destino administrativo inválido.');
    }
  }

  Future<String> save({
    required String collection,
    String? id,
    required Map<String, dynamic> data,
    Map<String, dynamic>? privateJobData,
  }) async {
    final documentId = id ?? _firestore.collection(collection).doc().id;
    _requireTarget(collection, documentId);
    final canonical = _firestore.collection(collection).doc(documentId);
    final projection = _firestore
        .collection('beta_public_catalog')
        .doc(collection)
        .collection('items')
        .doc(documentId);
    final privateJob = _firestore.collection('job_private').doc(documentId);
    final published =
        data['published'] != false &&
        data['active'] != false &&
        !isPermanentlyDeleted(data);
    final publicData = published ? publicProjection(data) : null;

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(canonical);
      final existingProjection = await transaction.get(projection);
      if (existing.exists && isPermanentlyDeleted(existing.data())) {
        throw StateError(
          'Conteúdo excluído logicamente não pode ser restaurado.',
        );
      }
      transaction.set(canonical, {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (publicData == null) {
        if (existingProjection.exists) transaction.delete(projection);
      } else {
        transaction.set(projection, {
          'visibility': 'public',
          'sourceId': documentId,
          'schemaVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'publicData': publicData,
        });
      }
      if (collection == 'jobs' && privateJobData != null) {
        transaction.set(privateJob, privateJobData, SetOptions(merge: true));
      }
    });
    return documentId;
  }

  Future<void> softDelete({required String collection, required String id}) {
    _requireTarget(collection, id);
    final canonical = _firestore.collection(collection).doc(id);
    final projection = _firestore
        .collection('beta_public_catalog')
        .doc(collection)
        .collection('items')
        .doc(id);
    return _firestore.runTransaction((transaction) async {
      final current = await transaction.get(canonical);
      if (!current.exists) throw StateError('Conteúdo não encontrado.');
      if (isPermanentlyDeleted(current.data())) {
        return;
      }
      transaction.update(canonical, {
        'active': false,
        'published': false,
        'deleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(projection);
    });
  }

  Future<void> setPublished({
    required String collection,
    required String id,
    required bool published,
  }) async {
    final canonical = _firestore.collection(collection).doc(id);
    final snapshot = await canonical.get();
    if (!snapshot.exists) throw StateError('Conteúdo não encontrado.');
    final current = snapshot.data()!;
    if (isPermanentlyDeleted(current)) {
      throw StateError('Conteúdo excluído logicamente não pode ser publicado.');
    }
    await save(
      collection: collection,
      id: id,
      data: {...current, 'published': published},
    );
  }

  Future<void> reorderUtilities(List<({String id, int order})> ordered) =>
      reorderContent('utilities', ordered);

  Future<void> reorderContent(
    String collection,
    List<({String id, int order})> ordered,
  ) async {
    BetaEnvironment.requireReady();
    BetaEnvironment.requireFirebaseProject(_firestore.app.options.projectId);
    if (!editableCollections.contains(collection) ||
        ordered.length > 200 ||
        ordered.any(
          (item) =>
              item.order < 0 || item.id.trim().isEmpty || item.id.contains('/'),
        ) ||
        ordered.map((item) => item.id).toSet().length != ordered.length) {
      throw ArgumentError('Ordem de conteúdo inválida.');
    }
    // Keep the Rules document-access budget bounded: every pair is checked
    // against the Admin authorization record and its canonical/projection
    // counterpart, so move at most eight pairs per transaction.
    const transactionChunkSize = 8;
    for (
      var offset = 0;
      offset < ordered.length;
      offset += transactionChunkSize
    ) {
      final chunk = ordered.skip(offset).take(transactionChunkSize).toList();
      final sources = [
        for (final item in chunk)
          _firestore.collection(collection).doc(item.id),
      ];
      final projections = [
        for (final item in chunk)
          _firestore
              .collection('beta_public_catalog')
              .doc(collection)
              .collection('items')
              .doc(item.id),
      ];
      await _firestore.runTransaction((transaction) async {
        final sourceSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        final projectionSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (var i = 0; i < chunk.length; i++) {
          sourceSnapshots.add(await transaction.get(sources[i]));
          projectionSnapshots.add(await transaction.get(projections[i]));
        }
        for (var i = 0; i < chunk.length; i++) {
          transaction.update(sources[i], {
            'order': chunk[i].order,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (projectionSnapshots[i].exists) {
            transaction.update(projections[i], {
              'publicData.order': chunk[i].order,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else if (sourceSnapshots[i].data()?['published'] != false &&
              sourceSnapshots[i].data()?['active'] != false &&
              !isPermanentlyDeleted(sourceSnapshots[i].data())) {
            throw StateError(
              'Projeção pública precisa ser revisada antes da ordem.',
            );
          }
        }
      });
    }
  }

  Future<void> saveHomePage(
    Map<String, dynamic> data, {
    required bool publish,
  }) async {
    BetaEnvironment.requireReady();
    BetaEnvironment.requireFirebaseProject(_firestore.app.options.projectId);
    final pages = _firestore.collection('home_pages');
    final batch = _firestore.batch();
    batch.set(pages.doc('draft'), {
      ...data,
      'published': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (publish) {
      batch.set(pages.doc('published'), {
        ...data,
        'published': true,
        'active': true,
        'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'version': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
