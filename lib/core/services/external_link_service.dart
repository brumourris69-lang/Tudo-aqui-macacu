import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/external_url.dart';
import '../config/local_search_environment.dart';
import 'metrics_service.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternalUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> openUrl(
  BuildContext context,
  String url,
  String label, {
  ExternalUrlLauncher launcher = _launchExternalUrl,
}) async {
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
  if (target.scheme.toLowerCase() == 'tel') {
    final shouldCall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.call_outlined),
        title: const Text('Ligar para este estabelecimento?'),
        content: Text('O telefone informado é ${target.path}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (shouldCall != true || !context.mounted) return;
  }
  unawaited(
    recordMetric('external_click', target: label, targetType: 'external'),
  );
  var opened = false;
  try {
    opened = await launcher(target);
  } on PlatformException {
    opened = false;
  } on MissingPluginException {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Não foi possível abrir $label.')));
  }
}
