import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'media_selection.dart';

const maxUploadImageBytes = 5 * 1024 * 1024;

/// UX validation; the callable independently checks the actual payload and the
/// provider decodes the file. Filename and client MIME type are never trusted.
String validateUploadImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxUploadImageBytes) {
    throw const FormatException('Escolha uma imagem de até 5 MiB.');
  }
  if (bytes.length >= 8 &&
      List.generate(8, (i) => bytes[i]).join(',') ==
          '137,80,78,71,13,10,26,10') {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'jpg';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'webp';
  }
  throw const FormatException('Use uma imagem JPEG, PNG ou WebP.');
}

/// Transient provider metadata. Only [selection]'s remote URL enters Home data.
class UploadedImage {
  UploadedImage._(
    this.selection,
    this.publicId,
    this.width,
    this.height,
    this.format,
    this.bytes,
  );
  final MediaSelection selection;
  final String publicId;
  final int width, height, bytes;
  final String format;

  factory UploadedImage.fromResponse(Object? response) {
    if (response is! Map || response.keys.any((key) => key is! String)) {
      throw const FormatException('Resposta de upload inválida.');
    }
    final value = Map<String, dynamic>.from(response);
    final url = value['secureUrl'];
    final id = value['publicId'];
    final format = value['format'];
    final width = value['width'],
        height = value['height'],
        bytes = value['bytes'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'res.cloudinary.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        id is! String ||
        !RegExp(
          r'^tudo-aqui-macacu/home/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
        ).hasMatch(id) ||
        format is! String ||
        !['jpg', 'png', 'webp'].contains(format) ||
        !RegExp(r'^/[^/]+/image/upload/v[0-9]+/').hasMatch(uri.path) ||
        !uri.path.endsWith('/$id.$format') ||
        width is! int ||
        width <= 0 ||
        height is! int ||
        height <= 0 ||
        bytes is! int ||
        bytes <= 0 ||
        bytes > maxUploadImageBytes) {
      throw const FormatException('Resposta de upload inválida.');
    }
    return UploadedImage._(
      MediaSelection.fromUrl(url as String),
      id,
      width,
      height,
      format,
      bytes,
    );
  }
}

abstract class ImageUploadService {
  Future<UploadedImage> upload(MediaSelection selection);
}

typedef UploadCallable = Future<Object?> Function(Map<String, dynamic> data);

class FirebaseImageUploadService implements ImageUploadService {
  FirebaseImageUploadService({UploadCallable? callable})
    : _callable = callable ?? _invoke;
  final UploadCallable _callable;

  static Future<Object?> _invoke(Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'uploadHomeImage',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
        )
        .call<Map<String, dynamic>>(data);
    return result.data;
  }

  @override
  Future<UploadedImage> upload(MediaSelection selection) async {
    if (!selection.isLocal) throw StateError('Selecione uma imagem local.');
    validateUploadImage(selection.bytes!);
    Object? result;
    try {
      result = await _callable({
        'purpose': 'home_logo',
        'imageBase64': base64Encode(selection.bytes!),
      });
    } on FirebaseFunctionsException catch (error) {
      final message = switch (error.code) {
        'unauthenticated' => 'Entre novamente para enviar a imagem.',
        'permission-denied' => 'Somente administradores podem enviar imagens.',
        'failed-precondition' =>
          'O upload ainda não foi configurado no servidor.',
        'invalid-argument' => 'Use uma imagem JPEG, PNG ou WebP de até 5 MiB.',
        _ => 'Não foi possível enviar. Tente novamente.',
      };
      throw FormatException(message);
    }
    return UploadedImage.fromResponse(result);
  }
}
