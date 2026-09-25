import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/firestore_collections.dart';

const metricActions = {
  'business_open',
  'business_whatsapp',
  'business_phone',
  'business_map',
  'business_instagram',
  'business_share',
  'favorite_add',
  'favorite_remove',
  'external_click',
  'notification_open',
  'utility_open',
  'coupon_open',
  'banner_view',
  'ad_view',
  'offer_open',
  'classified_view',
  'classified_contact',
  'adoption_view',
  'adoption_contact',
};

Future<void> recordMetric(
  String action, {
  String? target,
  String? targetType,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  if (!metricActions.contains(action)) return;
  try {
    await FirebaseFirestore.instance
        .collection(FirestoreCollections.metrics)
        .add({
          'action': action,
          'target': (target ?? '').trim(),
          'targetType': (targetType ?? '').trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
  } on FirebaseException catch (error) {
    debugPrint('Métrica não registrada: ${error.code}');
  }
}
