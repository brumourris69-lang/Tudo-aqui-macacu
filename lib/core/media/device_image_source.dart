import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'media_selection.dart';

abstract class ImageSelectionSource {
  Future<MediaSelection?> select();
  Future<MediaSelection?> recover();
}

class DeviceImageSource implements ImageSelectionSource {
  DeviceImageSource._();
  static final instance = DeviceImageSource._();
  final _picker = ImagePicker();
  Future<void>? _recovery;
  MediaSelection? _pending;

  /// Runs without blocking startup. Recovery stays in memory until the editor
  /// opens; it is never assigned a URL or written to a content document.
  Future<void> primeRecovery() => _recovery ??= _recoverOnce();

  Future<void> _recoverOnce() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final response = await _picker.retrieveLostData();
      if (response.exception != null) throw response.exception!;
      if (response.files?.isNotEmpty ?? false) {
        _pending = await _read(response.files!.first);
      }
    } catch (error) {
      debugPrint('Seleção de imagem não recuperada: $error');
    }
  }

  @override
  Future<MediaSelection?> recover() async {
    await primeRecovery();
    final value = _pending;
    _pending = null;
    return value;
  }

  @override
  Future<MediaSelection?> select() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    return file == null ? null : _read(file);
  }

  Future<MediaSelection> _read(XFile file) async =>
      MediaSelection.local(await file.readAsBytes(), fileName: file.name);
}
