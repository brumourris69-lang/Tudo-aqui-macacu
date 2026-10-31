import '../content/public_content_detail_repository.dart';
import 'internal_content_link.dart';

typedef PublicContentDataResolver =
    Future<Map<String, dynamic>?> Function({
      required String collection,
      required String id,
    });

/// Resolves a link only through the existing public, allowlisted backend.
class PublicContentLinkResolver {
  PublicContentLinkResolver({
    PublicContentDetailRepository? details,
    PublicContentDataResolver? resolve,
  }) : _details = details ?? PublicContentDetailRepository(),
       _resolve = resolve;

  final PublicContentDetailRepository _details;
  final PublicContentDataResolver? _resolve;

  Future<Map<String, dynamic>?> resolve(InternalContentLink link) =>
      (_resolve ?? _details.resolve)(
        collection: link.type.publicCollection,
        id: link.id,
      );
}
