import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'package:tudo_aqui_macacu/features/tourism/screens/tourism_config_editor.dart';

void main() {
  test('ícones existentes representam as duas categorias novas', () {
    expect(AppIcon.fromKey('guias_turisticos'), AppIcon.roteiros);
    expect(AppIcon.fromKey('historia_cidade'), AppIcon.turismo);
  });

  testWidgets('cadastro de local oferece as quatro áreas atuais', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ContentEditor(collection: 'routes')),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    for (final name in [
      'Pontos turísticos',
      'Trilhas',
      'Guias turísticos',
      'História da cidade',
    ]) {
      expect(find.text(name), findsWidgets);
    }
    await tester.tap(find.text('Guias turísticos').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editor de Turismo limita novas galerias a três imagens', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ContentEditor(collection: 'routes')),
    );
    await tester.scrollUntilVisible(
      find.text('Fotos do conteúdo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final galleryInput = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Links das imagens (Cloudinary)',
    );
    const urls = [
      'https://res.cloudinary.com/demo/image/upload/v1/a.jpg',
      'https://res.cloudinary.com/demo/image/upload/v1/b.jpg',
      'https://res.cloudinary.com/demo/image/upload/v1/c.jpg',
      'https://res.cloudinary.com/demo/image/upload/v1/d.jpg',
    ];
    await tester.enterText(galleryInput, urls.join('\n'));
    await tester.tap(find.text('Adicionar / atualizar fotos'));
    await tester.pump();

    expect(
      find.text('Turismo permite até 3 imagens por local.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(galleryInput).controller!.text,
      urls.join('\n'),
    );
    expect(find.text('Foto 1 · CAPA'), findsNothing);
  });

  testWidgets('Editor de Turismo bloqueia destino de mapa inseguro', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ContentEditor(collection: 'routes')),
    );
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Título ou nome',
    );
    await tester.enterText(title, 'Local de teste');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pontos turísticos').last);
    await tester.pumpAndSettle();
    final maps = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Link do Google Maps',
    );
    await tester.scrollUntilVisible(
      maps,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(maps, 'javascript:alert(1)');
    final save = find.text('Salvar alterações');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pump();

    expect(
      find.text('Use uma URL HTTPS ou um endereço geo: permitido.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editor de Turismo exige categoria classificada', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ContentEditor(collection: 'routes')),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Título ou nome',
      ),
      'Local sem categoria',
    );
    await tester.scrollUntilVisible(
      find.text('Salvar alterações'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Salvar alterações'));
    await tester.pump();
    expect(find.text('Selecione uma categoria para o local.'), findsOneWidget);
  });
  testWidgets('preview de configuração não salva automaticamente', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TourismConfigEditor(
          data: const {'title': 'Explore'},
          mediaHelper: const SizedBox.shrink(),
          onSave: (_) async {
            writes++;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Novo título');
    await tester.pump();
    expect(find.text('Novo título'), findsWidgets);
    expect(writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
