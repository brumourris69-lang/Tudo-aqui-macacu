import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/events/widgets/city_month_calendar.dart';

Widget _calendar({
  DateTime? selectedDate,
  Set<String> eventDays = const {},
  ValueChanged<DateTime>? onDateSelected,
  ValueChanged<int>? onMonthChanged,
}) => MaterialApp(
  home: Scaffold(
    body: CityMonthCalendar(
      month: DateTime(2026, 11),
      selectedDate: selectedDate,
      hasEvents: (day) => eventDays.contains(
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      ),
      onDateSelected: onDateSelected ?? (_) {},
      onMonthChanged: onMonthChanged ?? (_) {},
      onToday: () {},
    ),
  ),
);

void main() {
  testWidgets('shows a localized month, weekday headings, and event markers', (
    tester,
  ) async {
    await tester.pumpWidget(_calendar(eventDays: const {'2026-11-03'}));

    expect(find.text('novembro de 2026'), findsOneWidget);
    expect(find.text('seg'), findsOneWidget);
    expect(find.text('dom'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-day-2026-11-03')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-dot-2026-11-03')),
      findsOneWidget,
    );
  });

  testWidgets('selects a day and navigates to neighboring months', (
    tester,
  ) async {
    DateTime? selected;
    final changes = <int>[];
    await tester.pumpWidget(
      _calendar(
        onDateSelected: (day) => selected = day,
        onMonthChanged: changes.add,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-11-12')));
    expect(selected, DateTime(2026, 11, 12));
    await tester.tap(find.byKey(const ValueKey('city-calendar-previous')));
    await tester.tap(find.byKey(const ValueKey('city-calendar-next')));
    expect(changes, [-1, 1]);
  });

  testWidgets('fits a narrow screen with enlarged text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: _calendar(eventDays: const {'2026-11-03'}),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
