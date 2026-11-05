import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'public_share_content.dart';

const _shareChannel = MethodChannel('macacu/public-share');

enum PublicShareResult { shared, copied, failed }

Future<PublicShareResult> sharePublicContent(PublicShareContent content) async {
  late final String message;
  try {
    message = content.message;
  } on FormatException {
    return PublicShareResult.failed;
  }
  try {
    final shared = await _shareChannel.invokeMethod<bool>('share', {
      'title': message.split('\n').first,
      'text': message,
    });
    if (shared == true) return PublicShareResult.shared;
  } on MissingPluginException {
    // Keep a safe clipboard alternative if a platform share target is absent.
  } on PlatformException {
    // A chooser can be unavailable on restricted devices; try clipboard below.
  }

  try {
    await Clipboard.setData(ClipboardData(text: message));
    return PublicShareResult.copied;
  } on PlatformException {
    return PublicShareResult.failed;
  } on MissingPluginException {
    return PublicShareResult.failed;
  }
}

Future<void> sharePublicContentFromContext(
  BuildContext context,
  PublicShareContent content,
) async {
  final result = await sharePublicContent(content);
  if (!context.mounted) return;
  final invalidLinkNotice = content.hasInvalidPublicUrl
      ? ' Link inválido omitido; o texto orienta a encontrar o conteúdo no app.'
      : '';
  final message = switch (result) {
    PublicShareResult.shared =>
      'Escolha um aplicativo para compartilhar.$invalidLinkNotice',
    PublicShareResult.copied =>
      'Texto copiado. Você pode colar em qualquer aplicativo.$invalidLinkNotice',
    PublicShareResult.failed =>
      'Não foi possível compartilhar este conteúdo agora.',
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class PublicShareButton extends StatelessWidget {
  const PublicShareButton({
    super.key,
    required this.content,
    this.onShare,
    this.color,
    this.tooltip = 'Compartilhar',
  });

  final PublicShareContent content;
  final Future<void> Function()? onShare;
  final Color? color;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onShare ?? () => sharePublicContentFromContext(context, content),
    icon: Icon(Icons.share_outlined, color: color),
  );
}
