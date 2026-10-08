import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('splash progress clears footer artwork and respects safe areas', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 568), const Size(480, 853), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 24, bottom: 34)),
          child: SplashLoadingScreen(progress: .5, error: null, onRetry: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final progress = tester.getRect(find.byType(SplashProgressBar));
      // The first footer line starts at 92.4% of the unchanged cover artwork.
      final coverHeight = math.max(size.height, size.width * 1672 / 941);
      final footerTop = .924 * coverHeight - (coverHeight - size.height) / 2;
      expect(progress.bottom, lessThan(footerTop - 16));
      expect(progress.center.dx, closeTo(size.width / 2, .01));
    }
  });
}
