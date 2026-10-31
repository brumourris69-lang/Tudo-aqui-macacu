import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/share/public_share_content.dart';
import 'package:tudo_aqui_macacu/core/share/public_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('macacu/public-share');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'sends only public title and composed text to the native chooser',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return true;
          });

      final result = await sharePublicContent(
        const PublicShareContent(
          title: 'Comércio público',
          description: 'Descrição divulgável.',
        ),
      );

      expect(result, PublicShareResult.shared);
      expect(received?.method, 'share');
      expect(received?.arguments, {
        'title': 'Comércio público',
        'text':
            'Comércio público\nDescrição divulgável.\n'
            'Encontre no app Tudo Aqui Macacu.',
      });
    },
  );

  test('invalid content fails without invoking native sharing', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return true;
        });

    final result = await sharePublicContent(
      const PublicShareContent(title: '  '),
    );

    expect(result, PublicShareResult.failed);
    expect(calls, 0);
  });
}
