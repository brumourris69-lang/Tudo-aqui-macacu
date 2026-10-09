import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../auth/app_auth.dart';
import '../content/user_operations.dart';

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
  if (!isRegisteredUser(user)) return;
  if (!metricActions.contains(action)) return;
  try {
    await writeUserOperation('metric', {
      'action': action,
      'target': (target ?? '').trim(),
      'targetType': (targetType ?? '').trim(),
    });
  } catch (_) {
    // Telemetry must never prevent navigation; no payload/token in logs.
    debugPrint('Métrica não registrada.');
  }
}
