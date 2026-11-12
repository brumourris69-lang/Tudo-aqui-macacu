import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/spark_local_ad_preview.dart';

void main() {
  test('the reserved banner marker maps only in the SparkLocal build', () {
    expect(
      sparkLocalAdPreviewAssetFor(
        sparkLocalAdPreviewUrl,
        sparkLocalEnabled: true,
      ),
      sparkLocalAdPreviewAsset,
    );
    expect(
      sparkLocalAdPreviewAssetFor(
        sparkLocalAdPreviewUrl,
        sparkLocalEnabled: false,
      ),
      isNull,
    );
    expect(
      sparkLocalAdPreviewAssetFor(
        'https://images.example.test/other.png',
        sparkLocalEnabled: true,
      ),
      isNull,
    );
  });

  test('the reserved local image marker maps only for SparkLocal profiles', () {
    expect(
      sparkLocalBusinessPreviewAssetFor(
        sparkLocalAdPreviewUrl,
        sparkLocalEnabled: true,
      ),
      sparkLocalAdPreviewAsset,
    );
    expect(
      sparkLocalBusinessPreviewAssetFor(
        sparkLocalAdPreviewUrl,
        sparkLocalEnabled: false,
      ),
      isNull,
    );
    expect(
      sparkLocalBusinessPreviewAssetFor(
        'https://spark-local.invalid/another.png',
        sparkLocalEnabled: true,
      ),
      isNull,
    );
  });

  testWidgets('the selected local banner asset is a bundled PNG', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await rootBundle.load(sparkLocalAdPreviewAsset);
      expect(bytes.lengthInBytes, greaterThan(8));
      expect(
        bytes.buffer
            .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
            .take(8),
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      );
    });
  });
}
