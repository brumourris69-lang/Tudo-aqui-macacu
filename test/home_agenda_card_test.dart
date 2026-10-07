import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/home/widgets/home_agenda_card.dart';

void main() {
  testWidgets('shows supplied event data and preserves the single tap action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAgendaCard(
            title: 'Encontro de moradores',
            date: DateTime(2026, 11, 7),
            location: 'Praça do bairro',
            category: 'Comunidade',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('NOV'), findsOneWidget);
    expect(find.text('Praça do bairro'), findsOneWidget);
    expect(find.text('Comunidade'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.text('Encontro de moradores'));
    expect(taps, 1);
  });

  testWidgets('missing metadata never invents a date, category or photo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeAgendaCard(title: 'Evento sem detalhes', onTap: () {}),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('SET'), findsNothing);
    expect(find.text('Cultura'), findsNothing);
    expect(find.byIcon(Icons.location_on_outlined), findsNothing);
  });

  testWidgets('long event data fits narrow phones with enlarged text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 360.0, 412.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: HomeAgendaCard(
                  title: 'Encontro comunitário com um nome bastante longo',
                  date: DateTime(2026, 12, 28),
                  location: 'Endereço comprido de um espaço comunitário local',
                  category: 'Uma categoria com nome comprido',
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
