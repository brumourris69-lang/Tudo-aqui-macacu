import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/media/spark_local_preview_assets.dart';
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

  test('five promotional markers resolve only in the SparkLocal build', () {
    expect(sparkLocalPromotionPreviewUrls, hasLength(5));
    expect(sparkLocalPromotionPreviewAssets, hasLength(5));
    for (var i = 0; i < sparkLocalPromotionPreviewUrls.length; i++) {
      expect(
        sparkLocalAdPreviewAssetFor(
          sparkLocalPromotionPreviewUrls[i],
          sparkLocalEnabled: true,
        ),
        sparkLocalPromotionPreviewAssets[i],
      );
      expect(
        sparkLocalAdPreviewAssetFor(
          sparkLocalPromotionPreviewUrls[i],
          sparkLocalEnabled: false,
        ),
        isNull,
      );
    }
    expect(
      sparkLocalAdPreviewAssetFor(
        'https://spark-local.invalid/promotions/arbitrary.jpg',
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

  test('the five fixed business gallery markers map only in SparkLocal', () {
    expect(sparkLocalBusinessGalleryPreviewUrls, hasLength(5));
    expect(sparkLocalBusinessGalleryPreviewAssets, hasLength(5));
    for (var i = 0; i < sparkLocalBusinessGalleryPreviewUrls.length; i++) {
      expect(
        sparkLocalBusinessPreviewAssetFor(
          sparkLocalBusinessGalleryPreviewUrls[i],
          sparkLocalEnabled: true,
        ),
        sparkLocalBusinessGalleryPreviewAssets[i],
      );
      expect(
        sparkLocalBusinessPreviewAssetFor(
          sparkLocalBusinessGalleryPreviewUrls[i],
          sparkLocalEnabled: false,
        ),
        isNull,
      );
    }
    expect(
      sparkLocalBusinessPreviewAssetFor(
        'https://spark-local.invalid/gallery/arbitrary.jpg',
        sparkLocalEnabled: true,
      ),
      isNull,
    );
  });

  testWidgets('the five synthetic photos are bundled JPEG assets', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final asset in sparkLocalBusinessGalleryPreviewAssets) {
        final bytes = await rootBundle.load(asset);
        final image = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        expect(image.length, greaterThan(3));
        expect(image.take(3), [0xff, 0xd8, 0xff]);
      }
    });
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

  testWidgets('five promotional banners are bundled 8:3 JPEG assets', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final asset in sparkLocalPromotionPreviewAssets) {
        final bytes = await rootBundle.load(asset);
        final image = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        expect(image.take(3), [0xff, 0xd8, 0xff]);
        final codec = await ui.instantiateImageCodec(image);
        final frame = await codec.getNextFrame();
        expect(frame.image.width / frame.image.height, closeTo(8 / 3, .01));
        frame.image.dispose();
        codec.dispose();
      }
    });
  });
}
