import '../policies/business_search_policy.dart';
import '../repositories/universal_search_repository.dart';
import 'business_search_index.dart';

/// Server ports only. No Firebase instance, SDK call, trigger or export.
abstract interface class BusinessIndexTransaction {
  Future<Map<String, dynamic>?> readCurrentEstablishment(String id);
  Future<void> replaceIndex(String indexId, BusinessSearchIndexEntry entry);
  Future<void> deleteIndex(String indexId);
}

abstract interface class BusinessIndexStore {
  Future<void> transaction(
    Future<void> Function(BusinessIndexTransaction tx) body,
  );

  /// Future query: prefixes array-contains anchor; optional group equality;
  /// orderBy document ID; startAfter last ID; limit 40. Never scan establishments.
  Future<List<BusinessIndexCandidate>> candidates({
    required String anchor,
    required BusinessSearchFilter filter,
    required String? afterIndexId,
    required int limit,
  });
  Future<Map<String, dynamic>?> readCurrentEstablishment(String id);
}

class BusinessIndexCandidate {
  const BusinessIndexCandidate(this.indexId, this.sourceId);
  final String indexId, sourceId;
}

class BusinessIndexSynchronizer {
  const BusinessIndexSynchronizer(this.store, this.authorizeImage);
  final BusinessIndexStore store;
  final PublicImageAuthorization authorizeImage;

  /// Call with event ID only, NOT its stale before/after snapshot. The eventual
  /// Firestore transaction reads current source and writes/deletes atomically.
  Future<void> synchronize(String id, {required DateTime now}) async {
    if (id.isEmpty || id.contains('/')) throw ArgumentError('ID inválido');
    await store.transaction((tx) async {
      final current = await tx.readCurrentEstablishment(id);
      final entry = current == null
          ? null
          : BusinessSearchIndexEntry.build(
              id,
              current,
              now: now,
              authorizeImage: authorizeImage,
            );
      final indexId = 'establishments__$id';
      if (entry == null) {
        await tx.deleteIndex(indexId);
      } else {
        await tx.replaceIndex(indexId, entry);
      }
    });
  }
}

class SearchServerAccess {
  const SearchServerAccess({
    required this.authenticated,
    required this.appVerified,
  });
  final bool authenticated, appVerified;
}

class BusinessSearchServer {
  const BusinessSearchServer(this.store, this.authorizeImage);
  final BusinessIndexStore store;
  final PublicImageAuthorization authorizeImage;

  /// Draft policy requires authentication AND App Check. No public direct read.
  /// Empty pages can have a next cursor: at most 40 candidates are examined.
  Future<BusinessSearchPage> search(
    BusinessSearchRequest request, {
    required SearchServerAccess access,
    required DateTime now,
  }) async {
    if (!access.authenticated || !access.appVerified) {
      throw StateError('Acesso à busca não validado.');
    }
    final candidates = await store.candidates(
      anchor: request.anchor,
      filter: request.filter,
      afterIndexId: request.cursor?.lastIndexId,
      limit: 40,
    );
    if (candidates.length > 40) {
      throw StateError('Limite do armazenamento excedido.');
    }
    final results = <BusinessSearchIndexEntry>[];
    String? last;
    var consumed = 0;
    for (final candidate in candidates) {
      consumed++;
      last = candidate.indexId;
      if (candidate.sourceId.isEmpty ||
          candidate.sourceId.contains('/') ||
          candidate.indexId != 'establishments__${candidate.sourceId}') {
        continue;
      }
      final current = await store.readCurrentEstablishment(candidate.sourceId);
      final entry = current == null
          ? null
          : BusinessSearchIndexEntry.build(
              candidate.sourceId,
              current,
              now: now,
              authorizeImage: authorizeImage,
            );
      if (entry == null ||
          !BusinessSearchPolicy.matchesCategory(
            entry.result.category,
            request.filter,
          ) ||
          !request.terms.every(
            (query) => entry.terms.any((word) => word.startsWith(query)),
          )) {
        continue;
      }
      results.add(entry);
      if (results.length == request.limit) break;
    }
    final mayHaveMore = consumed < candidates.length || candidates.length == 40;
    return BusinessSearchPage(
      results.map((entry) => entry.result),
      mayHaveMore && last != null
          ? BusinessSearchCursor(request.queryKey, last)
          : null,
    );
  }
}
