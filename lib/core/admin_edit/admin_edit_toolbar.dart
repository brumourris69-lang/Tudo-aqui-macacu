import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AdminEditToolbar extends StatelessWidget {
  const AdminEditToolbar({
    super.key,
    required this.preview,
    required this.dirty,
    required this.busy,
    required this.canPublish,
    required this.onPreview,
    required this.onSaveDraft,
    required this.onPublish,
    required this.onExit,
  });
  final bool preview, dirty, busy, canPublish;
  final VoidCallback onPreview, onSaveDraft, onPublish, onExit;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.ocean.withValues(alpha: .20)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview ? 'Visualizando como usuário' : 'Editando Home',
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (!preview) ...[
          const SizedBox(height: 4),
          Text(
            busy
                ? 'Salvando…'
                : dirty
                ? 'Alterações não salvas'
                : 'Toque no título para editar',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: busy ? null : onPreview,
              icon: Icon(
                preview ? Icons.arrow_back_rounded : Icons.visibility_outlined,
              ),
              label: Text(
                preview ? 'Voltar à edição' : 'Visualizar como usuário',
              ),
            ),
            if (!preview) ...[
              OutlinedButton(
                onPressed: busy || !dirty ? null : onSaveDraft,
                child: const Text('Salvar rascunho'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.ocean),
                onPressed: busy || !canPublish ? null : onPublish,
                child: const Text('Publicar'),
              ),
              TextButton(
                onPressed: busy ? null : onExit,
                child: const Text('Sair'),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
