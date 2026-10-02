import 'dart:typed_data';
import 'media_url_service.dart';

enum MediaSelectionKind { empty, remote, local }

/// A device image has no persistible URL. Local bytes are preview-only.
class MediaSelection {
  const MediaSelection.empty()
    : kind = MediaSelectionKind.empty,
      url = '',
      bytes = null,
      name = null;
  const MediaSelection.existing(String value)
    : kind = MediaSelectionKind.remote,
      url = value,
      bytes = null,
      name = null;
  MediaSelection.local(Uint8List value, {required String fileName})
    : kind = MediaSelectionKind.local,
      url = '',
      bytes = Uint8List.fromList(value).asUnmodifiableView(),
      name = fileName;

  factory MediaSelection.fromUrl(String value) {
    // Validate the single input before normalization can extract a URL from
    // unrelated text (including a temporary device reference).
    if (!_validUrl(value.trim())) {
      throw const FormatException('Informe uma URL de imagem válida.');
    }
    final normalized = normalizeImageUrl(value);
    if (!_validUrl(normalized)) {
      throw const FormatException('Informe uma URL de imagem válida.');
    }
    return MediaSelection.existing(normalized);
  }

  final MediaSelectionKind kind;
  final String url;
  final Uint8List? bytes;
  final String? name;
  bool get isLocal => kind == MediaSelectionKind.local;
  bool get isEmpty =>
      kind == MediaSelectionKind.empty || (!isLocal && url.isEmpty);

  static bool _validUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        !RegExp(r'\s').hasMatch(value);
  }

  /// The only persistence conversion. It never returns bytes, names or paths.
  String requireRemoteUrl() {
    if (isLocal) {
      throw StateError('Envie a imagem antes de salvar ou publicar.');
    }
    if (isEmpty) return '';
    if (!_validUrl(url)) {
      throw const FormatException('Informe uma URL de imagem válida.');
    }
    return url;
  }
}
