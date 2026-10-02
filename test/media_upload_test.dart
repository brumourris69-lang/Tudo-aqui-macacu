import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/media/device_image_source.dart';
import 'package:tudo_aqui_macacu/core/media/media_selection.dart';
import 'package:tudo_aqui_macacu/core/media/media_upload_service.dart';
import 'package:tudo_aqui_macacu/core/media/single_image_selector.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const original = 'https://example.com/old.png';
const uploadId = 'tudo-aqui-macacu/home/00000000-0000-4000-8000-000000000001';
const uploadedUrl =
    'https://res.cloudinary.com/test-cloud/image/upload/v1/$uploadId.png';
Uint8List photo() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
MediaSelection local() => MediaSelection.local(photo(), fileName: 'device.png');
Map<String, dynamic> response([Map<String, dynamic> changes = const {}]) => {
  'secureUrl': uploadedUrl,
  'publicId': uploadId,
  'width': 1,
  'height': 1,
  'format': 'png',
  'bytes': photo().length,
  ...changes,
};

class Gallery implements ImageSelectionSource {
  @override
  Future<MediaSelection?> recover() async => null;
  @override
  Future<MediaSelection?> select() async => local();
}

Future<void> mount(
  WidgetTester tester,
  ImageUploadService uploader, {
  MediaSelection? initial,
  bool enabled = true,
}) async {
  var value = initial ?? local();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => SingleImageSelector(
              value: value,
              source: Gallery(),
              uploadService: uploader,
              enabled: enabled,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MediaSelection selected(WidgetTester tester) =>
    tester.widget<SingleImageSelector>(find.byType(SingleImageSelector)).value;

Future<void> mountHome(
  WidgetTester tester,
  ImageUploadService uploader,
  List<Map<String, dynamic>> writes,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomeEditor(
        loadConfiguration: () async => {
          'visual': {'logoUrl': original},
        },
        saveConfiguration: (data, _) async => writes.add(data),
        imageSource: Gallery(),
        imageUploadService: uploader,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('external replacement ignores previous upload completion', (
    tester,
  ) async {
    final completion = Completer<Object?>();
    await mount(
      tester,
      FirebaseImageUploadService(callable: (_) => completion.future),
    );
    await tester.tap(find.text('Enviar imagem'));
    await tester.pump();
    tester
        .widget<SingleImageSelector>(find.byType(SingleImageSelector))
        .onChanged(const MediaSelection.existing(original));
    await tester.pump();
    completion.complete(response());
    await tester.pumpAndSettle();
    expect(selected(tester).url, original);
    expect(tester.takeException(), isNull);
  });
  test(
    'permission rejection is surfaced safely without server internals',
    () async {
      final service = FirebaseImageUploadService(
        callable: (_) async {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'transport internals',
          );
        },
      );
      await expectLater(
        service.upload(local()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Somente administradores podem enviar imagens.',
          ),
        ),
      );
    },
  );
  test('uploading keeps immutable preview and cannot be persisted', () {
    final image = local();
    final pending = image.startUpload();
    expect(pending.isUploading, isTrue);
    expect(pending.isLocal, isTrue);
    expect(pending.bytes, same(image.bytes));
    expect(pending.requireRemoteUrl, throwsStateError);
    expect(pending.retrySelection().bytes, same(image.bytes));
  });
  test('client checks PNG JPEG WebP bytes and rejects HEIC and fake MIME', () {
    expect(validateUploadImage(photo()), 'png');
    expect(validateUploadImage(Uint8List.fromList([255, 216, 255])), 'jpg');
    expect(
      validateUploadImage(Uint8List.fromList(ascii.encode('RIFF1234WEBP'))),
      'webp',
    );
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(ascii.encode('....ftypheic')),
      Uint8List.fromList(ascii.encode('image/png')),
    ]) {
      expect(() => validateUploadImage(bytes), throwsFormatException);
    }
  });
  test('client rejects oversize before requesting server', () async {
    var calls = 0;
    final service = FirebaseImageUploadService(
      callable: (_) async {
        calls++;
        return response();
      },
    );
    final image = MediaSelection.local(
      Uint8List(maxUploadImageBytes + 1),
      fileName: 'big.png',
    );
    await expectLater(service.upload(image), throwsFormatException);
    expect(calls, 0);
  });
  test(
    'service sends only bytes and fixed purpose, returns original remote URL',
    () async {
      Map<String, dynamic>? sent;
      final service = FirebaseImageUploadService(
        callable: (data) async {
          sent = data;
          return response();
        },
      );
      final result = await service.upload(local());
      expect(sent!.keys.toSet(), {'purpose', 'imageBase64'});
      expect(sent!['purpose'], 'home_logo');
      expect(base64Decode(sent!['imageBase64'] as String), photo());
      expect(result.selection.requireRemoteUrl(), uploadedUrl);
      expect(result.publicId, uploadId);
      expect(result.width, 1);
      expect(result.bytes, photo().length);
      expect(() => result.selection.startUpload(), throwsStateError);
    },
  );
  test(
    'invalid server and provider results cannot create a remote selection',
    () async {
      for (final invalid in [
        null,
        'bad',
        {},
        response({'secureUrl': 'http://example.com/a.png'}),
        response({'secureUrl': 'https://evil.example/a.png'}),
        response({'publicId': 'other'}),
        response({'format': 'gif'}),
        response({'width': 0}),
        response({'bytes': maxUploadImageBytes + 1}),
      ]) {
        final service = FirebaseImageUploadService(
          callable: (_) async => invalid,
        );
        await expectLater(service.upload(local()), throwsFormatException);
      }
    },
  );
  testWidgets('local offers upload and uploading locks edits with progress', (
    tester,
  ) async {
    final completion = Completer<Object?>();
    var calls = 0;
    await mount(
      tester,
      FirebaseImageUploadService(
        callable: (_) {
          calls++;
          return completion.future;
        },
      ),
    );
    expect(find.text('Enviar imagem'), findsOneWidget);
    await tester.tap(find.text('Enviar imagem'));
    await tester.pump();
    expect(calls, 1);
    expect(selected(tester).isUploading, isTrue);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Trocar imagem'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Remover imagem'))
          .onPressed,
      isNull,
    );
    completion.complete(response());
    await tester.pumpAndSettle();
    expect(selected(tester).kind, MediaSelectionKind.remote);
    expect(selected(tester).url, uploadedUrl);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets(
    'immediate upload failure retains bytes and explicit retry succeeds',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        FirebaseImageUploadService(
          callable: (_) async {
            calls++;
            if (calls == 1) throw StateError('offline');
            return response();
          },
        ),
      );
      final bytes = selected(tester).bytes;
      await tester.tap(find.text('Enviar imagem'));
      await tester.pumpAndSettle();
      expect(selected(tester).kind, MediaSelectionKind.local);
      expect(selected(tester).bytes, same(bytes));
      expect(find.text('Tentar novamente'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(selected(tester).url, uploadedUrl);
    },
  );
  testWidgets('invalid result retains local preview', (tester) async {
    await mount(
      tester,
      FirebaseImageUploadService(
        callable: (_) async => response({'secureUrl': 'file:///cache.png'}),
      ),
    );
    await tester.tap(find.text('Enviar imagem'));
    await tester.pumpAndSettle();
    expect(selected(tester).kind, MediaSelectionKind.local);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
  testWidgets('ordinary disabled view cannot trigger upload', (tester) async {
    var calls = 0;
    await mount(
      tester,
      FirebaseImageUploadService(
        callable: (_) async {
          calls++;
          return response();
        },
      ),
      enabled: false,
    );
    expect(find.text('Enviar imagem'), findsNothing);
    expect(calls, 0);
  });
  testWidgets('disposed selector ignores a late upload result', (tester) async {
    final completion = Completer<Object?>();
    await mount(
      tester,
      FirebaseImageUploadService(callable: (_) => completion.future),
    );
    await tester.tap(find.text('Enviar imagem'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    completion.complete(response());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('URL advanced bypasses upload and remains compatible', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      FirebaseImageUploadService(
        callable: (_) async {
          calls++;
          return response();
        },
      ),
      initial: const MediaSelection.existing(original),
    );
    await tester.tap(find.text('Trocar imagem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar por URL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), uploadedUrl);
    await tester.tap(find.text('Usar imagem'));
    await tester.pumpAndSettle();
    expect(selected(tester).url, uploadedUrl);
    expect(calls, 0);
  });
  testWidgets(
    'Home keeps old reference, blocks uploading and saves remote only on explicit action',
    (tester) async {
      final completion = Completer<Object?>();
      final writes = <Map<String, dynamic>>[];
      await mountHome(
        tester,
        FirebaseImageUploadService(callable: (_) => completion.future),
        writes,
      );
      tester
          .widget<SingleImageSelector>(find.byType(SingleImageSelector))
          .onChanged(local());
      await tester.pump();
      await tester.tap(find.text('Enviar imagem'));
      await tester.pump();
      final dynamic state = tester.state(find.byType(HomeEditor));
      await state.save(false);
      await state.save(true);
      expect(writes, isEmpty);
      expect(selected(tester).isUploading, isTrue);
      completion.complete(response());
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(selected(tester).url, uploadedUrl);
      await state.save(false);
      expect((writes.single['visual'] as Map)['logoUrl'], uploadedUrl);
      await state.save(true);
      expect(writes.length, 2);
      expect((writes.last['visual'] as Map)['logoUrl'], uploadedUrl);
    },
  );
}
