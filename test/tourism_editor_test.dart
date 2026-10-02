import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';
import 'package:tudo_aqui_macacu/features/tourism/screens/tourism_config_editor.dart';

void main() {
  testWidgets('cadastro de local oferece as quatro categorias', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ContentEditor(collection: 'routes')),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    for (final name in [
      'Cachoeiras',
      'Trilhas',
      'Pontos turísticos',
      'Roteiros',
    ]) {
      expect(find.text(name), findsWidgets);
    }
    await tester.tap(find.text('Trilhas').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
