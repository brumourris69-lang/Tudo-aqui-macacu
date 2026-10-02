import 'package:flutter/material.dart';
import '../../../core/media/media_url_service.dart';
import '../widgets/tourism_cover.dart';

/// Persiste através do callback da tela administrativa, sem um segundo backend.
class TourismConfigEditor extends StatefulWidget {
  const TourismConfigEditor({
    super.key,
    required this.data,
    required this.onSave,
    required this.mediaHelper,
    this.category = false,
  });
  final Map<String, dynamic> data;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Widget mediaHelper;
  final bool category;

  @override
  State<TourismConfigEditor> createState() => _TourismConfigEditorState();
}

class _TourismConfigEditorState extends State<TourismConfigEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, description, image, order;
  late bool active;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(
      text: (widget.data[widget.category ? 'name' : 'title'] ?? '').toString(),
    );
    description = TextEditingController(
      text: (widget.data[widget.category ? 'description' : 'subtitle'] ?? '')
          .toString(),
    );
    image = TextEditingController(
      text: (widget.data['imageUrl'] ?? '').toString(),
    );
    order = TextEditingController(text: (widget.data['order'] ?? 0).toString());
    active = widget.data['active'] != false;
  }

  @override
  void dispose() {
    for (final controller in [title, description, image, order]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.onSave({
        widget.category ? 'name' : 'title': title.text.trim(),
        widget.category ? 'description' : 'subtitle': description.text.trim(),
        'imageUrl': cloudinaryOptimizedImageUrl(image.text),
        if (widget.category) ...{
          'order': int.parse(order.text),
          'active': active,
        },
      });
      if (mounted) Navigator.pop(context);
    } catch (error, stack) {
      debugPrint('Configuração de Turismo não salva: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.category ? 'Editar categoria' : 'Editar capa de Turismo',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TourismCover(
            title: title.text,
            description: description.text,
            imageUrl: cloudinaryOptimizedImageUrl(image.text),
          ),
          TextFormField(
            controller: title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Título'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Informe o título.' : null,
            onChanged: (_) => setState(() {}),
          ),
          TextFormField(
            controller: description,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Descrição curta'),
            onChanged: (_) => setState(() {}),
          ),
          TextFormField(
            controller: image,
            decoration: const InputDecoration(
              labelText: 'URL da imagem',
              helperText:
                  'Capa recomendada: 1600 × 1000 px (8:5). Use foto real fornecida por você.',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final uri = Uri.tryParse(normalizeImageUrl(v));
              return uri != null &&
                      ['https', 'http'].contains(uri.scheme) &&
                      uri.host.isNotEmpty
                  ? null
                  : 'Informe uma URL de imagem válida.';
            },
            onChanged: (_) => setState(() {}),
          ),
          TextButton.icon(
            onPressed: saving ? null : () => setState(() => image.clear()),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remover imagem'),
          ),
          widget.mediaHelper,
          if (widget.category) ...[
            TextFormField(
              controller: order,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: 'Ordem'),
              validator: (v) => int.tryParse(v ?? '') == null
                  ? 'Informe um número inteiro.'
                  : null,
            ),
            SwitchListTile(
              title: const Text('Categoria ativa'),
              value: active,
              onChanged: saving ? null : (v) => setState(() => active = v),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Salvando...' : 'Salvar e publicar'),
          ),
        ],
      ),
    ),
  );
}
