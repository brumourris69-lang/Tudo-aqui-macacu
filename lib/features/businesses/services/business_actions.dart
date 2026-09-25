import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/external_link_service.dart';
import '../../../core/services/metrics_service.dart';
import '../models/business.dart';

Future<void> openBusinessAction(
  BuildContext context,
  Business business, {
  required String action,
  required String url,
  required String label,
}) async {
  unawaited(
    recordMetric(action, target: business.favoriteKey, targetType: 'business'),
  );
  await openUrl(context, url, label);
}
