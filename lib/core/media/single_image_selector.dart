import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'device_image_source.dart';
import 'media_selection.dart';
import 'media_url_service.dart';

class SingleImageSelector extends StatefulWidget {
  const SingleImageSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.source,
    this.enabled = true,
    this.label = 'Imagem',
    this.aspectRatio = 1,
  });
  final MediaSelection value;
  final ValueChanged<MediaSelection> onChanged;
  final ImageSelectionSource? source;
  final bool enabled;
  final String label;
  final double aspectRatio;
  @override
  State<SingleImageSelector> createState() => _SingleImageSelectorState();
}

class _SingleImageSelectorState extends State<SingleImageSelector> {
  bool _selecting = false;
  int _generation = 0;
  MediaSelection _previousRemote = const MediaSelection.empty();
  ImageSelectionSource get _source =>
      widget.source ?? DeviceImageSource.instance;

  @override
  void initState() {
    super.initState();
    if (!widget.value.isLocal) _previousRemote = widget.value;
    _recover();
  }

  @override
  void didUpdateWidget(SingleImageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.value.isLocal && widget.value.isLocal) {
      _previousRemote = oldWidget.value;
    } else if (!widget.value.isLocal) {
      _previousRemote = widget.value;
    }
    if (!widget.enabled || oldWidget.value != widget.value) _generation++;
  }

  Future<void> _recover() async {
    if (!widget.enabled) return;
    final generation = _generation;
    try {
      final value = await _source.recover();
      if (mounted &&
          widget.enabled &&
          generation == _generation &&
          value != null) {
        widget.onChanged(value);
        _message('Imagem recuperada. Confira o preview antes de continuar.');
      }
    } catch (error) {
      debugPrint('Preview recuperado indisponível: $error');
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _choose() async {
    if (!widget.enabled || _selecting) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escolher imagem',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.ocean,
                ),
                title: const Text('Galeria do dispositivo'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              const Divider(),
              const Text(
                'Opções avançadas',
                style: TextStyle(color: AppColors.muted),
              ),
              ListTile(
                leading: const Icon(
                  Icons.link_rounded,
                  color: AppColors.orange,
                ),
                title: const Text('Adicionar por URL'),
                onTap: () => Navigator.pop(context, 'url'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || !widget.enabled || action == null) return;
    final generation = ++_generation;
    if (action == 'url') {
      final value = await showModalBottomSheet<MediaSelection>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _UrlEditor(initial: widget.value.url),
      );
      if (mounted &&
          widget.enabled &&
          generation == _generation &&
          value != null) {
        widget.onChanged(value);
      }
      return;
    }
    setState(() => _selecting = true);
    try {
      final value = await _source.select();
      if (mounted &&
          widget.enabled &&
          generation == _generation &&
          value != null) {
        widget.onChanged(value);
      }
    } catch (error) {
      debugPrint('Imagem não selecionada: $error');
      if (mounted && widget.enabled) {
        _message(
          'Não foi possível selecionar a imagem. A imagem anterior foi mantida.',
        );
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    Widget image;
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          value.isEmpty
              ? 'Adicionar imagem'
              : 'Não foi possível carregar esta imagem.',
          textAlign: TextAlign.center,
        ),
      ),
    );
    if (value.isEmpty) {
      image = fallback;
    } else if (value.isLocal) {
      image = Image.memory(
        value.bytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      image = Image.network(
        cloudinaryOptimizedImageUrl(value.url),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Material(
              color: AppColors.mist,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.enabled && !_selecting ? _choose : null,
                child: Semantics(
                  label: 'Preview de ${widget.label}',
                  child: image,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (value.isLocal)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Imagem selecionada — envio necessário antes de salvar ou publicar.',
              style: TextStyle(color: AppColors.ink),
            ),
          ),
        if (widget.enabled)
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _selecting ? null : _choose,
                style: FilledButton.styleFrom(backgroundColor: AppColors.ocean),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  _selecting
                      ? 'Selecionando…'
                      : value.isEmpty
                      ? 'Adicionar imagem'
                      : 'Trocar imagem',
                ),
              ),
              if (value.isLocal)
                TextButton(
                  onPressed: _selecting
                      ? null
                      : () => widget.onChanged(_previousRemote),
                  child: const Text('Cancelar seleção'),
                ),
              if (!value.isEmpty)
                TextButton.icon(
                  onPressed: _selecting
                      ? null
                      : () => widget.onChanged(const MediaSelection.empty()),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.orange,
                  ),
                  label: const Text('Remover imagem'),
                ),
            ],
          ),
      ],
    );
  }
}

class _UrlEditor extends StatefulWidget {
  const _UrlEditor({required this.initial});
  final String initial;
  @override
  State<_UrlEditor> createState() => _UrlEditorState();
}

class _UrlEditorState extends State<_UrlEditor> {
  late final controller = TextEditingController(text: widget.initial);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adicionar por URL',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL da imagem',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  try {
                    MediaSelection.fromUrl(value ?? '');
                    return null;
                  } on FormatException {
                    return 'Informe uma URL de imagem válida.';
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(
                          context,
                          MediaSelection.fromUrl(controller.text),
                        );
                      }
                    },
                    child: const Text('Usar imagem'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
