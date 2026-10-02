import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tudo_aqui_macacu/core/media/media_selection.dart';
import 'package:tudo_aqui_macacu/core/media/media_upload_service.dart';

const endpoint = 'https://upload.account.workers.dev/v1/home-logo';
const id = 'tudo-aqui-macacu/home/00000000-0000-4000-8000-000000000001';
MediaSelection photo() => MediaSelection.local(
  Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  fileName: 'photo.png',
);

void main() {
  test('malformed success JSON does not expose response body', () async {
    final service = WorkerImageUploadService(
      endpoint: endpoint,
      tokenReader: () async => 'token',
      clientFactory: () =>
          MockClient((_) async => http.Response('PRIVATE RESPONSE', 200)),
    );
    await expectLater(
      service.upload(photo()),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Resposta de upload inválida.',
        ),
      ),
    );
  });
  test(
    'Worker sends raw bytes and Firebase token, accepts validated URL',
    () async {
      final service = WorkerImageUploadService(
        endpoint: endpoint,
        tokenReader: () async => 'firebase-id-token',
        clientFactory: () => MockClient((request) async {
          expect(request.url.toString(), endpoint);
          expect(request.headers['Authorization'], 'Bearer firebase-id-token');
          expect(request.headers['Content-Type'], 'application/octet-stream');
          expect(request.bodyBytes, photo().bytes);
          return http.Response(
            jsonEncode({
              'secureUrl':
                  'https://res.cloudinary.com/test/image/upload/v1/$id.png',
              'publicId': id,
              'width': 1,
              'height': 1,
              'format': 'png',
              'bytes': 8,
            }),
            200,
          );
        }),
      );
      expect((await service.upload(photo())).publicId, id);
    },
  );

  test(
    'missing or unsafe endpoint never requests a token or sends bytes',
    () async {
      for (final url in [
        '',
        'http://upload.account.workers.dev/v1/home-logo',
        'https://evil.test/v1/home-logo',
        '$endpoint?secret=value',
      ]) {
        final service = WorkerImageUploadService(
          endpoint: url,
          tokenReader: () async => throw StateError('must not read auth'),
        );
        await expectLater(service.upload(photo()), throwsFormatException);
      }
    },
  );

  test('signed-out user cannot start upload', () async {
    final service = WorkerImageUploadService(
      endpoint: endpoint,
      tokenReader: () async => null,
      clientFactory: () =>
          MockClient((_) async => throw StateError('must not send')),
    );
    await expectLater(service.upload(photo()), throwsFormatException);
  });

  test('auth, rate and server errors are sanitized', () async {
    for (final code in [400, 401, 403, 429, 503, 502]) {
      final service = WorkerImageUploadService(
        endpoint: endpoint,
        tokenReader: () async => 'token',
        clientFactory: () =>
            MockClient((_) async => http.Response('PRIVATE DETAILS', code)),
      );
      try {
        await service.upload(photo());
        fail('should reject');
      } on FormatException catch (error) {
        expect(error.message, isNot(contains('PRIVATE DETAILS')));
      }
    }
  });

  test('transport exception never exposes token or provider details', () async {
    final service = WorkerImageUploadService(
      endpoint: endpoint,
      tokenReader: () async => 'token',
      clientFactory: () =>
          MockClient((_) async => throw Exception('PRIVATE TOKEN')),
    );
    await expectLater(
      service.upload(photo()),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Não foi possível enviar. Tente novamente.',
        ),
      ),
    );
  });

  test('Worker response cannot redirect image to arbitrary host', () async {
    final service = WorkerImageUploadService(
      endpoint: endpoint,
      tokenReader: () async => 'token',
      clientFactory: () => MockClient(
        (_) async => http.Response(
          jsonEncode({'secureUrl': 'https://evil.test/image.png'}),
          200,
        ),
      ),
    );
    await expectLater(service.upload(photo()), throwsFormatException);
  });
}
