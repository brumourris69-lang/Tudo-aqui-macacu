import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/external_url.dart';
import '../config/local_search_environment.dart';
import 'metrics_service.dart';

Future<void> openUrl(BuildContext context, String url, String label) async {
  if (LocalSearchEnvironment.enabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Links externos indisponíveis no ambiente local.'),
      ),
    );
    return;
  }
  final target = Uri.tryParse(url);
  if (target == null || url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label será disponibilizado quando você cadastrar o estabelecimento.',
        ),
      ),
    );
    return;
  }
  if (!isAllowedExternalUri(target)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('O link de $label não é permitido.')),
    );
    return;
  }
  unawaited(
    recordMetric('external_click', target: label, targetType: 'external'),
  );
  if (!await launchUrl(target, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Não foi possível abrir $label.')));
  }
}
