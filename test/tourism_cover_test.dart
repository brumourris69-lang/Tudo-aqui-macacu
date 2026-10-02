import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/widgets/tourism_cover.dart';

void main() {
  testWidgets('capas se adaptam à largura e texto ampliado sem overflow', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 850));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 850),
              textScaler: const TextScaler.linear(1.8),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: TourismCover(
                  title: 'Pontos turísticos',
                  description: 'Explore por categoria',
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(TourismPlaceholder), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    }
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('controle de edição usa callback específico', (tester) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TourismCover(title: 'Trilhas', onEdit: () => edits++),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Editar Trilhas'));
    expect(edits, 1);
  });
}
