import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'internal_content_link.dart';

typedef InternalContentPageResolver =
    Future<Widget?> Function(InternalContentLink link);

/// Resolves the received link and replaces this temporary route with its page.
class IncomingContentLinkPage extends StatefulWidget {
  const IncomingContentLinkPage({
    super.key,
    required this.link,
    required this.resolvePage,
  });

  final InternalContentLink? link;
  final InternalContentPageResolver resolvePage;

  @override
  State<IncomingContentLinkPage> createState() =>
      _IncomingContentLinkPageState();
}

class _IncomingContentLinkPageState extends State<IncomingContentLinkPage> {
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
    }
  }

  Future<void> _resolve() async {
    final link = widget.link;
    if (!mounted || link == null || _loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget
          .resolvePage(link)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (page == null) {
        setState(() {
          _loading = false;
          _failed = false;
        });
        return;
      }
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Voltar',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Abrir conteúdo'),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.sky),
                  SizedBox(height: 16),
                  Text('Carregando conteúdo…'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _failed ? Icons.wifi_off_rounded : Icons.link_off_rounded,
                    color: AppColors.sky,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _failed
                        ? 'Não foi possível carregar este conteúdo.'
                        : widget.link == null
                        ? 'Este link não é válido.'
                        : 'Este conteúdo não está disponível.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Verifique a conexão e tente novamente.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _resolve,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
      ),
    ),
  );
}
