import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('home category grid uses compact tiles on narrow phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [HomeCategoryGrid(categories: homeCatalog)],
          ),
        ),
      ),
    );

    final tile = find.byType(CategoryTile).first;
    expect(tester.getSize(tile).height, lessThanOrEqualTo(175));
    expect(tester.takeException(), isNull);
  });

  testWidgets('home category grid remains compact on larger screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [HomeCategoryGrid(categories: homeCatalog)],
          ),
        ),
      ),
    );

    final tile = find.byType(CategoryTile).first;
    expect(tester.getSize(tile).height, lessThanOrEqualTo(185));
    expect(tester.takeException(), isNull);
  });
}
