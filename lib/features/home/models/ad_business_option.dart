import 'package:cloud_firestore/cloud_firestore.dart';

/// Minimal Admin-facing establishment data used to link an ad to its target.
class AdBusinessOption {
  const AdBusinessOption({
    required this.id,
    required this.name,
    required this.category,
    required this.canBePublished,
  });

  factory AdBusinessOption.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    bool allowUnspecifiedPublication = true,
  }) {
    final data = document.data() ?? const <String, dynamic>{};
    return AdBusinessOption(
      id: document.id,
      name: (data['name'] ?? data['title'] ?? '').toString().trim(),
      category: (data['category'] ?? '').toString().trim(),
      canBePublished: isEligibleAdBusiness(
        data,
        allowUnspecifiedPublication: allowUnspecifiedPublication,
      ),
    );
  }

  final String id;
  final String name;
  final String category;
  final bool canBePublished;
}

String? validAdBusinessId(Object? value) {
  if (value is! String) return null;
  final id = value;
  if (id.isEmpty ||
      id != id.trim() ||
      id.length > 128 ||
      id == '.' ||
      id == '..' ||
      id.contains('/')) {
    return null;
  }
  return id;
}

/// Matches the catalog's legacy defaults while rejecting explicit invalid states.
bool isEligibleAdBusiness(
  Map<String, dynamic> data, {
  bool allowUnspecifiedPublication = true,
}) =>
    (data.containsKey('published')
        ? data['published'] == true
        : allowUnspecifiedPublication) &&
    (!data.containsKey('active') || data['active'] == true) &&
    (!data.containsKey('deleted') || data['deleted'] == false) &&
    (!data.containsKey('deletedAt') || data['deletedAt'] == null);

bool hasVisibleAdDestination(
  Map<String, dynamic> ad,
  Map<String, Map<String, dynamic>> publishedBusinesses, {
  bool allowUnspecifiedPublication = true,
}) {
  final businessId = validAdBusinessId(ad['businessId']);
  if (businessId == null) return false;
  final business = publishedBusinesses[businessId];
  return business != null &&
      isEligibleAdBusiness(
        business,
        allowUnspecifiedPublication: allowUnspecifiedPublication,
      );
}
