import '../../../core/config/local_search_environment.dart';
import '../../../core/config/beta_environment.dart';
import '../../../core/config/spark_public_catalog_environment.dart';
import '../../../core/config/staging_environment.dart';
import '../../../core/content/beta_public_catalog.dart';
import '../../../core/content/secure_backend.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../features/search/repositories/local_universal_search_repository.dart';
import '../models/public_job.dart';

typedef PublicJobResolver = Future<PublicJob?> Function(String id);
typedef SparkPublicJobProjectionResolver =
    Future<Map<String, dynamic>?> Function(String id);
typedef PublicJobCallableInvoker =
    Future<dynamic> Function(String operation, Map<String, dynamic> data);

/// Resolves public job details through demo, staging, or safe public-content
/// transport. The normal transport remains debug-opt-in only.
class PublicJobDetailsRepository {
  PublicJobDetailsRepository({
    PublicJobResolver? resolveJob,
    PublicJobCallableInvoker? invokeStaging,
    bool Function()? stagingEnabledForTest,
    void Function()? requireStagingReadyForTest,
    void Function()? requireSparkCatalogReadyForTest,
    SparkPublicJobProjectionResolver? resolveSparkProjectionForTest,
  }) : _resolveJob =
           resolveJob ?? LocalUniversalSearchRepository.resolvePublicJob,
       _invokeStaging = invokeStaging ?? SecureBackend.invoke,
       _stagingEnabled =
           stagingEnabledForTest ?? (() => StagingEnvironment.enabled),
       _requireStagingReady =
           requireStagingReadyForTest ?? StagingEnvironment.requireReady,
       _requireSparkCatalogReady =
           requireSparkCatalogReadyForTest ?? _checkSparkCatalogReady,
       _resolveSparkProjection =
           resolveSparkProjectionForTest ?? _loadSparkProjection;

  final PublicJobResolver _resolveJob;
  final PublicJobCallableInvoker _invokeStaging;
  final bool Function() _stagingEnabled;
  final void Function() _requireStagingReady;
  final void Function() _requireSparkCatalogReady;
  final SparkPublicJobProjectionResolver _resolveSparkProjection;

  static void _checkSparkCatalogReady() {
    final firestore = FirebaseFirestore.instance;
    SparkPublicCatalogEnvironment.requireReady(
      actualProjectId: firestore.app.options.projectId,
    );
  }

  static Future<Map<String, dynamic>?> _loadSparkProjection(String id) =>
      BetaPublicCatalog(
        FirebaseFirestore.instance,
      ).get(collection: 'jobs', id: id);

  Future<PublicJob?> resolveById(String id) async {
    PublicJob.validateId(id);
    if (_stagingEnabled() &&
        (LocalSearchEnvironment.enabled ||
            BetaEnvironment.enabled ||
            SparkPublicCatalogEnvironment.enabled)) {
      throw StateError(
        'Ambientes de homologação e distribuição não coexistem.',
      );
    }
    if (LocalSearchEnvironment.enabled) return _resolveJob(id);
    if (BetaEnvironment.enabled) {
      BetaEnvironment.requireReady();
      final firestore = FirebaseFirestore.instance;
      BetaEnvironment.requireFirebaseProject(firestore.app.options.projectId);
      final data = await BetaPublicCatalog(
        firestore,
      ).get(collection: 'jobs', id: id);
      return data == null ? null : PublicJob.fromMap({...data, 'id': id});
    }
    if (SparkPublicCatalogEnvironment.enabled) {
      _requireSparkCatalogReady();
      final data = await _resolveSparkProjection(id);
      return data == null ? null : PublicJob.fromMap({...data, 'id': id});
    }
    if (_stagingEnabled()) {
      _requireStagingReady();
      final response = await _invokeStaging('getPublicJob', {'id': id});
      return PublicJob.fromSearchResponse(response, requestedId: id);
    }
    if (SecureBackend.normalDebugAuthorized) {
      final response = await _invokeStaging('getPublicContentDetail', {
        'collection': 'jobs',
        'id': id,
      });
      return PublicJob.fromSearchResponse(response, requestedId: id);
    }
    throw StateError('Detalhes de vagas aguardam ativação autorizada.');
  }
}
