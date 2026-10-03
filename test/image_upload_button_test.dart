import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/media/device_image_source.dart';
import 'package:tudo_aqui_macacu/core/media/image_upload_button.dart';
import 'package:tudo_aqui_macacu/core/media/media_selection.dart';
import 'package:tudo_aqui_macacu/core/media/media_upload_service.dart';

const id = 'tudo-aqui-macacu/home/00000000-0000-4000-8000-000000000001';
const url = 'https://res.cloudinary.com/demo/image/upload/v1/$id.png';

class Source implements ImageSelectionSource {
  @override
  Future<MediaSelection?> recover() async => null;
  @override
  Future<MediaSelection?> select() async => MediaSelection.local(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    fileName: 'photo.png',
  );
}

class Uploader implements ImageUploadService {
  final result = Completer<UploadedImage>();
  @override
  Future<UploadedImage> upload(MediaSelection selection) => result.future;
}

UploadedImage uploaded() => UploadedImage.fromResponse({
  'secureUrl': url,
  'publicId': id,
  'width': 1,
  'height': 1,
  'format': 'png',
  'bytes': 68,
});

Future<void> mount(
  WidgetTester tester,
  Uploader uploader,
  ValueChanged<String> onUploaded, {
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ImageUploadButton(
          enabled: enabled,
          source: Source(),
          uploadService: uploader,
          onUploaded: onUploaded,
        ),
      ),
    ),
  );
}

Future<void> choose(WidgetTester tester) async {
  await tester.tap(find.text('Selecionar e enviar imagem'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Adicionar imagem').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Galeria do dispositivo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only an uploaded and confirmed URL leaves the dialog', (
    tester,
  ) async {
    final uploader = Uploader();
    String? selected;
    await mount(tester, uploader, (value) => selected = value);
    await choose(tester);
    expect(selected, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Usar imagem'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Enviar imagem'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
          .onPressed,
      isNull,
    );
    uploader.result.complete(uploaded());
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Usar imagem'));
    await tester.pumpAndSettle();
    expect(selected, url);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancelling a local selection preserves the editor', (
    tester,
  ) async {
    String? selected;
    await mount(tester, Uploader(), (value) => selected = value);
    await choose(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('failed upload permits retry without persisting local bytes', (
    tester,
  ) async {
    final uploader = Uploader();
    String? selected;
    await mount(tester, uploader, (value) => selected = value);
    await choose(tester);
    await tester.tap(find.text('Enviar imagem'));
    await tester.pump();
    uploader.result.completeError(const FormatException('Falha de teste'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Usar imagem'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('disabled editor does not open the uploader', (tester) async {
    await mount(tester, Uploader(), (_) {}, enabled: false);
    await tester.tap(find.text('Selecionar e enviar imagem'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
