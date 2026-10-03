import 'package:flutter/material.dart';
import 'device_image_source.dart';
import 'media_selection.dart';
import 'media_upload_service.dart';
import 'single_image_selector.dart';

/// Only completed remote selections leave this dialog. Uploading does not
/// publish content, and cancelling keeps the editor's previous URL intact.
class ImageUploadButton extends StatelessWidget {
  const ImageUploadButton({
    super.key,
    required this.onUploaded,
    this.enabled = true,
    this.source,
    this.uploadService,
  });

  final ValueChanged<String> onUploaded;
  final bool enabled;
  final ImageSelectionSource? source;
  final ImageUploadService? uploadService;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    icon: const Icon(Icons.photo_library_outlined),
    label: const Text('Selecionar e enviar imagem'),
    onPressed: !enabled
        ? null
        : () async {
            final url = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _UploadDialog(
                source: source,
                service: uploadService ?? WorkerImageUploadService(),
              ),
            );
            if (context.mounted && url != null) onUploaded(url);
          },
  );
}

class _UploadDialog extends StatefulWidget {
  const _UploadDialog({required this.source, required this.service});
  final ImageSelectionSource? source;
  final ImageUploadService service;

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  MediaSelection selection = const MediaSelection.empty();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !selection.isUploading,
    child: AlertDialog(
      title: const Text('Imagem do dispositivo'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: SingleImageSelector(
            value: selection,
            source: widget.source,
            uploadService: widget.service,
            aspectRatio: 16 / 9,
            onChanged: (value) => setState(() => selection = value),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: selection.isUploading
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: selection.isEmpty || selection.isLocal
              ? null
              : () => Navigator.pop(context, selection.requireRemoteUrl()),
          child: const Text('Usar imagem'),
        ),
      ],
    ),
  );
}
