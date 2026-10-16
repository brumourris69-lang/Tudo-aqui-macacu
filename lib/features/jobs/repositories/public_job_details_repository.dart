import '../../../core/config/local_search_environment.dart';
import '../../../features/search/repositories/local_universal_search_repository.dart';
import '../models/public_job.dart';

typedef PublicJobResolver = Future<PublicJob?> Function(String id);

/// Resolves public job details through the isolated getPublicJob callable.
/// Production transport stays disabled until a separately authorized stage.
class PublicJobDetailsRepository {
  PublicJobDetailsRepository({PublicJobResolver? resolveJob})
    : _resolveJob = resolveJob ?? LocalUniversalSearchRepository.resolvePublicJob;

  final PublicJobResolver _resolveJob;

  Future<PublicJob?> resolveById(String id) async {
    PublicJob.validateId(id);
    if (!LocalSearchEnvironment.enabled) {
      throw StateError('Detalhes de vagas aguardam ativação autorizada.');
    }
    return _resolveJob(id);
  }
}
