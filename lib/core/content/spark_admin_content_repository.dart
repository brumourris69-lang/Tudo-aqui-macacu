import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/beta_environment.dart';
import '../config/local_search_environment.dart';
import '../config/spark_local_environment.dart';
import '../config/spark_public_catalog_environment.dart';
import '../config/staging_environment.dart';
import '../../features/businesses/models/establishment_listing_level.dart';

/// Direct Firestore writer for validated Beta and Spark distribution editors.
///
/// Authorization is enforced by `firestore.beta.rules`: the caller must have
/// a current, out-of-band provisioned Admin claim and authorization record.
/// Canonical content and its public allowlisted projection are changed in one
/// transaction so drafts and hidden content never remain publicly readable.
abstract interface class SparkAdminContentOperations {
  /// Generates an ID without writing a document.
  String reserveId(String collection);

  Future<String> save({
    required String collection,
    String? id,
    required Map<String, dynamic> data,
    Map<String, dynamic>? privateJobData,
  });

  Future<void> softDelete({required String collection, required String id});
}

class SparkAdminContentRepository implements SparkAdminContentOperations {
  SparkAdminContentRepository(this._firestore);

  /// The same Rules-backed transaction is used by the explicitly validated
  /// Beta, SparkLocal, and Spark distribution identities. Conflicting Beta and
  /// distribution build flags fail closed instead of selecting a writer.
  static bool shouldUseTransactionalAdmin({
    required bool betaBuild,
    required bool sparkDistributionBuild,
  }) {
    if (betaBuild && sparkDistributionBuild) {
      throw StateError('Identidades Beta e Spark não podem coexistir.');
    }
    return betaBuild || sparkDistributionBuild;
  }

  static bool get usesTransactionalAdmin => shouldUseTransactionalAdmin(
    betaBuild: BetaEnvironment.enabled,
    sparkDistributionBuild: SparkPublicCatalogEnvironment.enabled,
  );

  static const basicProjectionCollection = 'establishments_basic';
  static const premiumProjectionCollection = 'establishments_premium';

  final FirebaseFirestore _firestore;

  @override
  String reserveId(String collection) =>
      _firestore.collection(collection).doc().id;

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
    'businessId',
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

  static const _premiumEstablishmentFields = <String>{
    'description',
    'shortDescription',
    'iconKey',
    'imageUrl',
    'logoUrl',
    'maps',
    'mapsUrl',
    'whatsapp',
    'instagram',
    'type',
    'contactUrl',
    'link',
    'hours',
    'additionalInfo',
    'galleryUrls',
    'videoUrls',
    'services',
    'products',
    'artwork',
    'featured',
    'open',
    'options',
  };

  static String _projectionCollection(String collection) =>
      collection == 'establishments' ? basicProjectionCollection : collection;

  static Map<String, dynamic> publicProjection(
    Map<String, dynamic> source, {
    String? collection,
  }) {
    final projection = collection == 'establishments'
        ? _basicEstablishmentProjection(source)
        : _fullPublicProjection(source, collection: collection);
    _validatePublicTitle(projection);
    return projection;
  }

  /// Returns only the complementary Premium fields while the canonical
  /// contract is effective at [now]. The caller stores these fields separately
  /// from the Basic catalog projection.
  static Map<String, dynamic>? premiumProjectionData(
    Map<String, dynamic> source, {
    required DateTime now,
  }) {
    final level = EstablishmentListingLevel.fromMap(source);
    if (level.effectiveTierAt(now) != ListingTier.premium) return null;
    return <String, dynamic>{
      for (final entry in source.entries)
        if (_premiumEstablishmentFields.contains(entry.key) &&
            entry.value != null)
          entry.key: entry.value,
    };
  }

  static EstablishmentListingLevel validateListingLevelForSave(
    Map<String, dynamic> source, {
    required DateTime now,
  }) {
    final level = EstablishmentListingLevel.fromMap(source);
    if (!level.canBeSavedAt(now)) {
      throw const FormatException(
        'O nível Premium exige um vencimento válido e futuro.',
      );
    }
    return level;
  }

  static Map<String, dynamic> _basicEstablishmentProjection(
    Map<String, dynamic> source,
  ) {
    const stringFields = {
      'name',
      'title',
      'address',
      'location',
      'phone',
      'category',
      'subcategory',
    };
    final projection = <String, dynamic>{
      for (final field in stringFields)
        if (source[field] is String) field: source[field],
      if (source['order'] is int) 'order': source['order'],
    };
    return projection;
  }

  static Map<String, dynamic> _fullPublicProjection(
    Map<String, dynamic> source, {
    String? collection,
  }) => <String, dynamic>{
    for (final entry in source.entries)
      if (_publicFields.contains(entry.key) &&
          (entry.key != 'businessId' || collection == 'ads') &&
          entry.value != null)
        entry.key: entry.value,
  };

  static void _validatePublicTitle(Map<String, dynamic> projection) {
    final title = projection['name'] ?? projection['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('Conteúdo público precisa de um título.');
    }
    if (projection.length > 44) {
      throw const FormatException(
        'Conteúdo público excede o limite de campos.',
      );
    }
  }

  static bool isPermanentlyDeleted(Map<String, dynamic>? source) =>
      source?['deleted'] == true ||
      (source?['deletedAt'] != null && source?['deletedAt'] is! FieldValue);

  void _requireEnvironment() {
    if (BetaEnvironment.enabled && SparkPublicCatalogEnvironment.enabled) {
      throw StateError('Identidades Beta e Spark não podem coexistir.');
    }
    if (BetaEnvironment.enabled) {
      BetaEnvironment.requireReady();
      BetaEnvironment.requireFirebaseProject(_firestore.app.options.projectId);
      return;
    }
    if (LocalSearchEnvironment.enabled ||
        SparkLocalEnvironment.enabled ||
        StagingEnvironment.enabled) {
      throw StateError(
        'A publicação comercial Spark não pode usar demo ou homologação.',
      );
    }
    SparkPublicCatalogEnvironment.requireReady(
      actualProjectId: _firestore.app.options.projectId,
    );
  }

  void _requireTarget(String collection, String id) {
    _requireEnvironment();
    if (!editableCollections.contains(collection) ||
        id.trim().isEmpty ||
        id.contains('/') ||
        id == '.' ||
        id == '..') {
      throw ArgumentError('Destino administrativo inválido.');
    }
  }

  @override
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
        .doc(_projectionCollection(collection))
        .collection('items')
        .doc(documentId);
    final premiumProjection = collection == 'establishments'
        ? _firestore
              .collection('beta_public_catalog')
              .doc(premiumProjectionCollection)
              .collection('items')
              .doc(documentId)
        : null;
    final privateJob = _firestore.collection('job_private').doc(documentId);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(canonical);
      final existingProjection = await transaction.get(projection);
      if (existing.exists && isPermanentlyDeleted(existing.data())) {
        throw StateError(
          'Conteúdo excluído logicamente não pode ser restaurado.',
        );
      }
      final mergedData = {...?existing.data(), ...data};
      final savedAt = DateTime.now().toUtc();
      final listingLevel = collection == 'establishments'
          ? validateListingLevelForSave(mergedData, now: savedAt)
          : EstablishmentListingLevel.fromMap(mergedData);
      final published =
          mergedData['published'] != false &&
          mergedData['active'] != false &&
          !isPermanentlyDeleted(mergedData);
      final publicData = published
          ? publicProjection(mergedData, collection: collection)
          : null;
      final premiumData = published
          ? premiumProjectionData(mergedData, now: savedAt)
          : null;
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
      if (premiumProjection != null) {
        if (premiumData == null || listingLevel.premiumUntil == null) {
          transaction.delete(premiumProjection);
        } else {
          transaction.set(premiumProjection, {
            'visibility': 'public',
            'sourceId': documentId,
            'schemaVersion': 1,
            'updatedAt': FieldValue.serverTimestamp(),
            'listingTier': ListingTier.premium.name,
            'premiumUntil': Timestamp.fromDate(
              listingLevel.premiumUntil!.toUtc(),
            ),
            'publicData': premiumData,
          });
        }
      }
      if (collection == 'jobs' && privateJobData != null) {
        transaction.set(privateJob, privateJobData, SetOptions(merge: true));
      }
    });
    return documentId;
  }

  @override
  Future<void> softDelete({required String collection, required String id}) {
    _requireTarget(collection, id);
    final canonical = _firestore.collection(collection).doc(id);
    final projection = _firestore
        .collection('beta_public_catalog')
        .doc(_projectionCollection(collection))
        .collection('items')
        .doc(id);
    final premiumProjection = collection == 'establishments'
        ? _firestore
              .collection('beta_public_catalog')
              .doc(premiumProjectionCollection)
              .collection('items')
              .doc(id)
        : null;
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
      if (premiumProjection != null) transaction.delete(premiumProjection);
    });
  }

  Future<void> setPublished({
    required String collection,
    required String id,
    required bool published,
  }) => save(collection: collection, id: id, data: {'published': published});

  Future<void> reorderUtilities(List<({String id, int order})> ordered) =>
      reorderContent('utilities', ordered);

  Future<void> reorderContent(
    String collection,
    List<({String id, int order})> ordered,
  ) async {
    _requireEnvironment();
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
              .doc(_projectionCollection(collection))
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
    _requireEnvironment();
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
