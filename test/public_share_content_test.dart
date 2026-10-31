import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/share/public_share_content.dart';
import 'package:tudo_aqui_macacu/core/share/public_share_service.dart';
import 'package:flutter/material.dart';

void main() {
  group('PublicShareContent', () {
    test('uses a useful in-app search fallback when no public URL exists', () {
      const content = PublicShareContent(
        title: 'Cachoeira Modelo',
        description: 'Um lugar especial para conhecer.',
      );

      expect(
        content.message,
        'Cachoeira Modelo\nUm lugar especial para conhecer.\n'
        'Encontre no app Tudo Aqui Macacu.',
      );
    });

    test('includes only an explicit safe public HTTPS link', () {
      const content = PublicShareContent(
        title: 'Feira da Cidade',
        description: 'Evento cultural.',
        publicUrl: 'https://public.example/events/feira',
      );

      expect(content.message, contains('https://public.example/events/feira'));
      expect(content.message, isNot(contains('wa.me')));
    });

    test('rejects insecure or credential-bearing links and uses fallback', () {
      for (final url in [
        'http://example.com/item',
        'https://user:password@example.com/item',
        'javascript:alert(1)',
      ]) {
        expect(
          PublicShareContent(title: 'Conteúdo', publicUrl: url).message,
          contains('Encontre no app Tudo Aqui Macacu.'),
          reason: url,
        );
        expect(
          PublicShareContent(
            title: 'Conteúdo',
            publicUrl: url,
          ).hasInvalidPublicUrl,
          isTrue,
          reason: url,
        );
      }
    });

    test('normalizes controls and bounds the shared description', () {
      final content = PublicShareContent(
        title: '  Loja\nSegura  ',
        description: 'a' * 400,
      );

      expect(content.message, startsWith('Loja Segura\n'));
      expect(content.message.length, lessThan(300));
      expect(content.message, isNot(contains('\n\n')));
    });

    test('does not produce shareable content for an empty title', () {
      expect(
        () => const PublicShareContent(title: '  ').message,
        throwsFormatException,
      );
    });
  });

  testWidgets('share button exposes an accessible action and callback', (
    tester,
  ) async {
    var shares = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicShareButton(
            content: const PublicShareContent(title: 'Conteúdo público'),
            onShare: () async => shares++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Compartilhar'), findsOneWidget);
    await tester.tap(find.byTooltip('Compartilhar'));
    await tester.pump();
    expect(shares, 1);
  });
}
