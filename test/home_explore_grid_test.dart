import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('Onde comer ou Pedir fica centralizado no topo do Explorar', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [320.0, 393.0, 600.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                HomeCategoryGrid(
                  categories: exploreCatalog,
                  onCategoryTap: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final featured = tester.widget<CategoryTile>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CategoryTile && widget.category.name == 'Onde comer?',
        ),
      );
      expect(featured.displayLabel, 'Onde comer ou Pedir?');

      final rect = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CategoryTile && widget.category.name == 'Onde comer?',
        ),
      );
      expect(rect.center.dx, closeTo(width / 2, .5), reason: 'width=$width');
      expect(rect.top, lessThan(50), reason: 'width=$width');
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });
}
