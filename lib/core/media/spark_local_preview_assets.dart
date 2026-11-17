/// Fixed local-only image fixture for visually testing SparkLocal content.
///
/// The `.invalid` host is reserved. SparkLocal maps this exact marker to an
/// asset bundled with the app, so the preview makes no network request. Other
/// builds and URLs keep their normal network-image behavior.
const sparkLocalAdPreviewUrl =
    'https://spark-local.invalid/banner-cachoeiras.png';

const sparkLocalAdPreviewAsset = 'assets/images/home-tourism-cachoeiras.png';

/// Fixed, non-routable SparkLocal-only promotional banner markers.
const sparkLocalPromotionPreviewUrls = <String>[
  'https://spark-local.invalid/promotions/cafe-manha.jpg',
  'https://spark-local.invalid/promotions/descubra-macacu.jpg',
  'https://spark-local.invalid/promotions/sabores-locais.jpg',
  'https://spark-local.invalid/promotions/estilo-local.jpg',
  'https://spark-local.invalid/promotions/noite-de-pizza.jpg',
];

const sparkLocalPromotionPreviewAssets = <String>[
  'assets/images/spark-local-promotions/cafe-manha.jpg',
  'assets/images/spark-local-promotions/descubra-macacu.jpg',
  'assets/images/spark-local-promotions/sabores-locais.jpg',
  'assets/images/spark-local-promotions/estilo-local.jpg',
  'assets/images/spark-local-promotions/noite-de-pizza.jpg',
];

/// Fixed, non-routable markers and bundled photos for the SparkLocal-only
/// business gallery preview. The distribution variants never map these URLs.
const sparkLocalBusinessGalleryPreviewUrls = <String>[
  'https://spark-local.invalid/gallery/exterior.jpg',
  'https://spark-local.invalid/gallery/interior.jpg',
  'https://spark-local.invalid/gallery/patio.jpg',
  'https://spark-local.invalid/gallery/cafe.jpg',
  'https://spark-local.invalid/gallery/bolo.jpg',
];

const sparkLocalBusinessGalleryPreviewAssets = <String>[
  'assets/images/spark-local-gallery/exterior.jpg',
  'assets/images/spark-local-gallery/interior.jpg',
  'assets/images/spark-local-gallery/patio.jpg',
  'assets/images/spark-local-gallery/cafe.jpg',
  'assets/images/spark-local-gallery/bolo.jpg',
];

String? sparkLocalAdPreviewAssetFor(
  String imageUrl, {
  required bool sparkLocalEnabled,
}) {
  if (!sparkLocalEnabled) return null;
  final normalized = imageUrl.trim();
  if (normalized == sparkLocalAdPreviewUrl) return sparkLocalAdPreviewAsset;
  final index = sparkLocalPromotionPreviewUrls.indexOf(normalized);
  return index < 0 ? null : sparkLocalPromotionPreviewAssets[index];
}

/// Reuses only the fixed fixture marker for a local SparkLocal business photo.
/// Arbitrary asset paths and URLs never take the local asset path.
String? sparkLocalBusinessPreviewAssetFor(
  String imageUrl, {
  required bool sparkLocalEnabled,
}) {
  if (!sparkLocalEnabled) return null;
  final normalized = imageUrl.trim();
  if (normalized == sparkLocalAdPreviewUrl) return sparkLocalAdPreviewAsset;
  final index = sparkLocalBusinessGalleryPreviewUrls.indexOf(normalized);
  return index < 0 ? null : sparkLocalBusinessGalleryPreviewAssets[index];
}
