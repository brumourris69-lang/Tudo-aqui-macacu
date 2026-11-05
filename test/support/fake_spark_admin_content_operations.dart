import 'package:tudo_aqui_macacu/core/content/spark_admin_content_repository.dart';

class FakeSparkAdminContentOperations implements SparkAdminContentOperations {
  FakeSparkAdminContentOperations({this.onSave});

  final Future<void> Function({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
    Map<String, dynamic>? privateJobData,
  })?
  onSave;
  final reservedCollections = <String>[];
  final saves =
      <
        ({
          String collection,
          String id,
          Map<String, dynamic> data,
          Map<String, dynamic>? privateJobData,
        })
      >[];
  final deletions = <({String collection, String id})>[];
  var _nextId = 0;

  @override
  String reserveId(String collection) {
    reservedCollections.add(collection);
    return 'fixture-$collection-${++_nextId}';
  }

  @override
  Future<String> save({
    required String collection,
    String? id,
    required Map<String, dynamic> data,
    Map<String, dynamic>? privateJobData,
  }) async {
    final documentId = id ?? reserveId(collection);
    saves.add((
      collection: collection,
      id: documentId,
      data: Map.of(data),
      privateJobData: privateJobData == null ? null : Map.of(privateJobData),
    ));
    await onSave?.call(
      collection: collection,
      id: documentId,
      data: Map.of(data),
      privateJobData: privateJobData == null ? null : Map.of(privateJobData),
    );
    return documentId;
  }

  @override
  Future<void> softDelete({
    required String collection,
    required String id,
  }) async {
    deletions.add((collection: collection, id: id));
  }
}
