import 'package:flutter/material.dart';
import '../../../core/admin_edit/admin_edit_session.dart';
import '../../../core/admin_edit/admin_edit_toolbar.dart';

/// Local content belongs to this pilot, never to the reusable edit session.
class HomeTitleEditPilot extends StatefulWidget {
  const HomeTitleEditPilot({
    super.key,
    required this.isAdmin,
    required this.publishedTitle,
    required this.onSave,
    required this.builder,
    this.onEnter,
  });
  final bool isAdmin;
  final String publishedTitle;
  final Future<void> Function(String title, bool publish) onSave;
  final Widget Function(
    String title,
    VoidCallback? onEdit,
    VoidCallback? onStart,
    bool active,
  )
  builder;
  final VoidCallback? onEnter;

  @override
  State<HomeTitleEditPilot> createState() => HomeTitleEditPilotState();
}

class HomeTitleEditPilotState extends State<HomeTitleEditPilot> {
  final session = AdminEditSession();
  String? _localTitle;
  String? _savedTitle;
  bool _busy = false;
  int _generation = 0;
  BuildContext? _sheetContext;
  BuildContext? _exitDialogContext;
  bool _confirmingExit = false;

  @override
  void initState() {
    super.initState();
    session.setAuthorized(widget.isAdmin);
  }

  @override
  void didUpdateWidget(HomeTitleEditPilot oldWidget) {
    super.didUpdateWidget(oldWidget);
    session.setAuthorized(widget.isAdmin);
    if (oldWidget.isAdmin && !widget.isAdmin) {
      _generation++;
      _localTitle = _savedTitle = null;
      _busy = false;
      final sheet = _sheetContext;
      final dialog = _exitDialogContext;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (sheet != null &&
            sheet.mounted &&
            ModalRoute.of(sheet)?.isCurrent == true) {
          Navigator.of(sheet).pop();
        }
        if (dialog != null &&
            dialog.mounted &&
            ModalRoute.of(dialog)?.isCurrent == true) {
          Navigator.of(dialog).pop();
        }
      });
    }
  }

  void _start() {
    if (!widget.isAdmin || session.active) return;
    _localTitle = _savedTitle = widget.publishedTitle;
    session.activate();
    widget.onEnter?.call();
  }

  Future<void> _edit() async {
    if (!widget.isAdmin || !session.active || session.preview || _busy) return;
    final generation = _generation;
    final initial = _localTitle!;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        _sheetContext = context;
        return _TitleEditor(initial: initial);
      },
    );
    _sheetContext = null;
    if (!mounted ||
        generation != _generation ||
        !widget.isAdmin ||
        value == null) {
      return;
    }
    setState(() => _localTitle = value);
    session.setDirty(value != _savedTitle);
  }

  Future<bool> _save(bool publish) async {
    if (!widget.isAdmin || !session.active || _busy) return false;
    final generation = _generation;
    final value = _localTitle!;
    setState(() => _busy = true);
    try {
      await widget.onSave(value, publish);
      if (!mounted || generation != _generation || !widget.isAdmin) {
        return false;
      }
      _savedTitle = value;
      session.setDirty(false);
      return true;
    } catch (error) {
      debugPrint('Título da Home não salvo: $error');
      if (mounted && generation == _generation && widget.isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar. Suas alterações continuam aqui.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  /// Used by the Home's tab navigation as well as the toolbar.
  Future<bool> requestExit() async {
    if (_busy || _confirmingExit) return false;
    if (!session.active) return true;
    if (session.dirty) {
      _confirmingExit = true;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) {
          _exitDialogContext = context;
          return AlertDialog(
            title: const Text('Alterações não salvas'),
            content: const Text(
              'Salve o rascunho ou descarte as alterações antes de sair.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continuar editando'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'discard'),
                child: const Text('Descartar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('Salvar rascunho'),
              ),
            ],
          );
        },
      );
      _confirmingExit = false;
      _exitDialogContext = null;
      if (!mounted || choice == null) return false;
      if (choice == 'save' && !await _save(false)) return false;
    }
    if (!mounted) return false;
    _generation++;
    _localTitle = _savedTitle = null;
    session.reset();
    return true;
  }

  @override
  void dispose() {
    _generation++;
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => PopScope(
      canPop: !session.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && session.active) requestExit();
      },
      child: Column(
        children: [
          widget.builder(
            session.active ? _localTitle! : widget.publishedTitle,
            session.active && !session.preview && !_busy ? _edit : null,
            widget.isAdmin && !session.active ? _start : null,
            session.active,
          ),
          if (widget.isAdmin && session.active)
            AdminEditToolbar(
              preview: session.preview,
              dirty: session.dirty,
              busy: _busy,
              canPublish: session.dirty || _localTitle != widget.publishedTitle,
              onPreview: session.togglePreview,
              onSaveDraft: () => _save(false),
              onPublish: () => _save(true),
              onExit: requestExit,
            ),
        ],
      ),
    ),
  );
}

class _TitleEditor extends StatefulWidget {
  const _TitleEditor({required this.initial});
  final String initial;
  @override
  State<_TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends State<_TitleEditor> {
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
                'Editar título',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Título principal',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o título.'
                    : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(context, controller.text.trim());
                      }
                    },
                    child: const Text('Concluir'),
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
