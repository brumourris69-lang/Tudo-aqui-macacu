import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class BetaSearchUnavailablePage extends StatelessWidget {
  const BetaSearchUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.soft,
    appBar: AppBar(title: const Text('Buscar em Macacu')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'Busca por texto indisponível nesta versão Beta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Para manter a versão sem serviços pagos, explore os conteúdos pelas categorias na tela inicial.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Voltar ao início'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
