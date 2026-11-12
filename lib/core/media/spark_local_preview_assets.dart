/// Fixed local-only image fixture for visually testing SparkLocal content.
///
/// The `.invalid` host is reserved. SparkLocal maps this exact marker to an
/// asset bundled with the app, so the preview makes no network request. Other
/// builds and URLs keep their normal network-image behavior.
const sparkLocalAdPreviewUrl =
    'https://spark-local.invalid/banner-cachoeiras.png';

const sparkLocalAdPreviewAsset = 'assets/images/home-tourism-cachoeiras.png';

String? sparkLocalAdPreviewAssetFor(
  String imageUrl, {
  required bool sparkLocalEnabled,
}) => sparkLocalEnabled && imageUrl.trim() == sparkLocalAdPreviewUrl
    ? sparkLocalAdPreviewAsset
    : null;

/// Reuses only the fixed fixture marker for a local SparkLocal business photo.
/// Arbitrary asset paths and URLs never take the local asset path.
String? sparkLocalBusinessPreviewAssetFor(
  String imageUrl, {
  required bool sparkLocalEnabled,
}) => sparkLocalEnabled && imageUrl.trim() == sparkLocalAdPreviewUrl
    ? sparkLocalAdPreviewAsset
    : null;
