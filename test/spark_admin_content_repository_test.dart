import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/spark_admin_content_repository.dart';

void main() {
  group('SparkAdminContentRepository.publicProjection', () {
    test('copies only approved public content fields', () {
      final projection = SparkAdminContentRepository.publicProjection({
        'name': 'Padaria Central',
        'category': 'Alimentação',
        'imageUrl': 'https://example.test/cover.jpg',
        'published': true,
        'active': true,
        'ownerEmail': 'private@example.test',
        'adminNotes': 'não publicar',
      });

      expect(projection, {
        'name': 'Padaria Central',
        'category': 'Alimentação',
        'imageUrl': 'https://example.test/cover.jpg',
      });
    });

    test('rejects a public projection without a title', () {
      expect(
        () => SparkAdminContentRepository.publicProjection({
          'description': 'sem nome',
        }),
        throwsFormatException,
      );
    });

    test('treats both deleted marker forms as permanent tombstones', () {
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({'deleted': true}),
        isTrue,
      );
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({
          'deleted': false,
          'deletedAt': DateTime.utc(2026, 10, 30),
        }),
        isTrue,
      );
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({
          'deleted': false,
          'deletedAt': null,
        }),
        isFalse,
      );
      expect(
        SparkAdminContentRepository.isPermanentlyDeleted({
          'deleted': false,
          'deletedAt': FieldValue.delete(),
        }),
        isFalse,
      );
      expect(SparkAdminContentRepository.isPermanentlyDeleted(null), isFalse);
    });
  });
}
