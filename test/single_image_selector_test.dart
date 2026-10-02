import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/media/device_image_source.dart';
import 'package:tudo_aqui_macacu/core/media/media_selection.dart';
import 'package:tudo_aqui_macacu/core/media/single_image_selector.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

const remote = 'https://example.com/logo.png';
MediaSelection local() => MediaSelection.local(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
  fileName: 'logo.png',
);

class FakeSource implements ImageSelectionSource {
  MediaSelection? result;
  MediaSelection? recovered;
  bool fails = false;
  int calls = 0;
  @override
  Future<MediaSelection?> recover() async => recovered;
  @override
  Future<MediaSelection?> select() async {
    calls++;
    if (fails) throw StateError('picker failed');
    return result;
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeSource source, {
  MediaSelection initial = const MediaSelection.existing(remote),
  bool enabled = true,
}) async {
  var value = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => SingleImageSelector(
              value: value,
              source: source,
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

MediaSelection selection(WidgetTester tester) =>
    tester.widget<SingleImageSelector>(find.byType(SingleImageSelector)).value;
Future<void> gallery(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Trocar imagem'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Galeria do dispositivo'));
  await tester.pumpAndSettle();
}

void main() {
  test('local bytes cannot become a persistent URL', () {
    final value = local();
    expect(value.url, isEmpty);
    expect(value.requireRemoteUrl, throwsStateError);
    expect(() => value.bytes![0] = 0, throwsUnsupportedError);
  });
  test('valid remote and empty preserve persistence representation', () {
    expect(const MediaSelection.existing(remote).requireRemoteUrl(), remote);
    expect(const MediaSelection.empty().requireRemoteUrl(), '');
    expect(MediaSelection.fromUrl(' $remote ').requireRemoteUrl(), remote);
    const cloudinary =
        'http://res.cloudinary.com/demo/image/upload/v1/logo.png';
    expect(
      const MediaSelection.existing(cloudinary).requireRemoteUrl(),
      cloudinary,
    );
  });
  test('temporary and malformed URLs are rejected', () {
    for (final url in [
      'file:///cache/a.png',
      'content://photo/a',
      'data:image/png;base64,a',
      'blob:a',
      r'C:\cache\a.png',
      '',
      'https://',
      'https://example.com/a b',
    ]) {
      expect(() => MediaSelection.fromUrl(url), throwsFormatException);
    }
  });
  testWidgets('remote preview uses network image and preserves URL', (
    tester,
  ) async {
    await mount(tester, FakeSource());
    expect(tester.widget<Image>(find.byType(Image)).image, isA<NetworkImage>());
    expect(selection(tester).requireRemoteUrl(), remote);
  });
  testWidgets('empty state offers selection without primary URL field', (
    tester,
  ) async {
    await mount(tester, FakeSource(), initial: const MediaSelection.empty());
    expect(
      find.widgetWithText(FilledButton, 'Adicionar imagem'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });
  testWidgets('gallery replaces preview only and cancel restores remote', (
    tester,
  ) async {
    final source = FakeSource()..result = local();
    await mount(tester, source);
    await gallery(tester);
    expect(source.calls, 1);
    expect(selection(tester).isLocal, isTrue);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(find.textContaining('envio necessário'), findsOneWidget);
    await tester.tap(find.text('Cancelar seleção'));
    await tester.pumpAndSettle();
    expect(selection(tester).requireRemoteUrl(), remote);
  });
  testWidgets('native cancellation keeps previous image', (tester) async {
    await mount(tester, FakeSource());
    await gallery(tester);
    expect(selection(tester).url, remote);
  });
  testWidgets('picker failure keeps previous image', (tester) async {
    await mount(tester, FakeSource()..fails = true);
    await gallery(tester);
    expect(selection(tester).url, remote);
    expect(find.textContaining('imagem anterior foi mantida'), findsOneWidget);
  });
  testWidgets('sheet cancellation never invokes picker', (tester) async {
    final source = FakeSource();
    await mount(tester, source);
    await tester.tap(find.widgetWithText(FilledButton, 'Trocar imagem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(source.calls, 0);
    expect(selection(tester).url, remote);
  });
  testWidgets('advanced URL validates then replaces remote', (tester) async {
    await mount(tester, FakeSource());
    await tester.tap(find.widgetWithText(FilledButton, 'Trocar imagem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar por URL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'file:///bad');
    await tester.tap(find.text('Usar imagem'));
    await tester.pumpAndSettle();
    expect(find.text('Informe uma URL de imagem válida.'), findsOneWidget);
    expect(selection(tester).url, remote);
    await tester.enterText(
      find.byType(TextFormField),
      'https://example.com/new.png',
    );
    await tester.tap(find.text('Usar imagem'));
    await tester.pumpAndSettle();
    expect(selection(tester).url, 'https://example.com/new.png');
  });
  testWidgets('remove emits empty reference without a device action', (
    tester,
  ) async {
    final source = FakeSource();
    await mount(tester, source);
    await tester.tap(find.text('Remover imagem'));
    await tester.pumpAndSettle();
    expect(selection(tester).isEmpty, isTrue);
    expect(source.calls, 0);
  });
  testWidgets('recovered image remains preview only', (tester) async {
    await mount(tester, FakeSource()..recovered = local());
    expect(selection(tester).isLocal, isTrue);
    expect(selection(tester).requireRemoteUrl, throwsStateError);
  });
  testWidgets('disabled selector exposes no editing controls', (tester) async {
    await mount(tester, FakeSource(), enabled: false);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  for (final publish in [false, true]) {
    testWidgets(
      'HomeEditor blocks local ${publish ? "publish" : "draft"} and keeps preview',
      (tester) async {
        final writes = <Map<String, dynamic>>[];
        await tester.binding.setSurfaceSize(const Size(1000, 6000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: HomeEditor(
              loadConfiguration: () async => {
                'visual': {'logoUrl': remote},
              },
              saveConfiguration: (data, _) async => writes.add(data),
              imageSource: FakeSource(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selector = tester.widget<SingleImageSelector>(
          find.byType(SingleImageSelector),
        );
        selector.onChanged(local());
        await tester.pump();
        final dynamic state = tester.state(find.byType(HomeEditor));
        await state.save(publish);
        await tester.pump();
        expect(writes, isEmpty);
        expect(selection(tester).isLocal, isTrue);
        expect(find.textContaining('O preview foi mantido'), findsOneWidget);
      },
    );
  }
  testWidgets('HomeEditor saves only remote or removed reference', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    await tester.binding.setSurfaceSize(const Size(1000, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeEditor(
          loadConfiguration: () async => {
            'visual': {'logoUrl': remote},
          },
          saveConfiguration: (data, _) async => writes.add(data),
          imageSource: FakeSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(HomeEditor));
    await state.save(false);
    expect((writes.last['visual'] as Map)['logoUrl'], remote);
    tester
        .widget<SingleImageSelector>(find.byType(SingleImageSelector))
        .onChanged(const MediaSelection.empty());
    await tester.pump();
    expect(writes.length, 1);
    await state.save(true);
    expect((writes.last['visual'] as Map)['logoUrl'], '');
  });
  testWidgets('HomeEditor invalid existing URL fails safely before writing', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeEditor(
          loadConfiguration: () async => {
            'visual': {'logoUrl': 'file:///cache/logo.png'},
          },
          saveConfiguration: (_, _) async => writes++,
          imageSource: FakeSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(HomeEditor));
    await state.save(false);
    await tester.pump();
    expect(writes, 0);
    expect(find.text('Informe uma URL de imagem válida.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
