import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourism_config.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_overview.dart';

void main() {
  testWidgets(
    'público não vê edição nem categorias inativas; admin edita a categoria correta',
    (tester) async {
      final config = TourismConfig.fromMap({
        'categories': {
          'trilhas': {'active': false},
        },
      });
      String? edited;
      Widget page(bool admin) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TourismOverview(
              config: config,
              admin: admin,
              onCategoryTap: (_) {},
              onEditHero: () {},
              onEditCategory: (c) => edited = c.key,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(false));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Trilhas'), findsNothing);
      await tester.pumpWidget(page(true));
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(5));
      await tester.ensureVisible(find.byTooltip('Editar Trilhas'));
      await tester.tap(find.byTooltip('Editar Trilhas'));
      expect(edited, 'trilhas');
    },
  );
}
