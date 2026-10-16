import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/tourism/models/tourist_spot.dart';
import 'package:tudo_aqui_macacu/redesigned_app.dart';

void main() {
  testWidgets('categoria de guias mantém roteiros legados em grupo separado', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TourismCategoryView(
          title: 'Guias turísticos',
          categoryKey: 'guias_turisticos',
          spots: [
            TouristSpot.fromData('roteiro', {
              'title': 'Roteiro legado',
              'category': 'roteiros',
            }),
            TouristSpot.fromData('guia', {
              'title': 'Guia histórico',
              'category': 'guias_turisticos',
            }),
          ],
        ),
      ),
    );
    final categoryList = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('Roteiro legado'),
      250,
      scrollable: categoryList,
    );
    expect(find.text('Roteiro legado'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Guia histórico'),
      250,
      scrollable: categoryList,
    );
    expect(find.text('Guia histórico'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Roteiros existentes'),
      250,
      scrollable: categoryList,
    );
    expect(find.text('Roteiros existentes'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });
}
