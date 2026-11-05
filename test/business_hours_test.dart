import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/features/businesses/widgets/business_hours.dart';

void main() {
  group('BusinessHoursSchedule', () {
    test('reads grouped Portuguese days and legacy 10h notation', () {
      final schedule = BusinessHoursSchedule.parse(
        'Seg-Sáb: 10h às 18h | Dom: Fechado',
      );

      expect(schedule, isNotNull);
      expect(schedule!.days[DateTime.monday]?.isOpen, isTrue);
      expect(schedule.days[DateTime.saturday]?.opensAtMinute, 10 * 60);
      expect(schedule.days[DateTime.sunday]?.isOpen, isFalse);
    });

    test('round trips the app schedule format without changing known days', () {
      final schedule = BusinessHoursSchedule.parse(
        'Seg-Sex: 09:00 às 18:00; Sáb: 09:00 às 13:00; Dom: Fechado',
      );

      expect(schedule, isNotNull);
      expect(
        BusinessHoursSchedule.parse(schedule!.toStorage())?.days,
        schedule.days,
      );
    });

    test('reports open and closed using Brasília wall time', () {
      final schedule = BusinessHoursSchedule.parse(
        'Seg-Sex: 09:00 às 18:00; Sáb: Fechado; Dom: Fechado',
      )!;

      // 2026-11-02 is Monday; 15:00 UTC is 12:00 in Brasília.
      expect(
        schedule.statusAt(DateTime.utc(2026, 11, 2, 15)),
        BusinessOpeningStatus.open,
      );
      expect(
        schedule.statusAt(DateTime.utc(2026, 11, 2, 21)),
        BusinessOpeningStatus.closed,
      );
      expect(
        schedule.statusAt(DateTime.utc(2026, 11, 8, 15)),
        BusinessOpeningStatus.closed,
      );
    });

    test(
      'supports an overnight schedule across the Brasília weekday boundary',
      () {
        final schedule = BusinessHoursSchedule.parse(
          'Seg: 22:00 às 02:00; Ter: 09:00 às 18:00',
        );

        expect(schedule, isNotNull);
        // Tuesday 02:30 UTC is Monday 23:30 in Brasília.
        expect(
          schedule!.statusAt(DateTime.utc(2026, 11, 3, 2, 30)),
          BusinessOpeningStatus.open,
        );
        // Tuesday 05:00 UTC is Tuesday 02:00 in Brasília: closing is exclusive.
        expect(
          schedule.statusAt(DateTime.utc(2026, 11, 3, 5)),
          BusinessOpeningStatus.closed,
        );
      },
    );

    test('does not infer status from equal or malformed time ranges', () {
      expect(BusinessHoursSchedule.parse('Seg: 09:00 às 09:00'), isNull);
      expect(BusinessHoursSchedule.parse('Seg: 25:00 às 02:00'), isNull);
    });

    test('describes the next close when open and next open when closed', () {
      final schedule = BusinessHoursSchedule.parse(
        'Seg: 09:00 às 18:00; Ter: 08:00 às 12:00',
      )!;

      expect(
        schedule.nextEventAt(DateTime.utc(2026, 11, 2, 15))?.label,
        'Fecha hoje às 18h',
      );
      expect(
        schedule.nextEventAt(DateTime.utc(2026, 11, 2, 10))?.label,
        'Abre hoje às 09h',
      );
      expect(
        schedule.nextEventAt(DateTime.utc(2026, 11, 2, 22))?.label,
        'Abre amanhã às 08h',
      );
    });

    test('finds the next known weekday across missing days and week wrap', () {
      final schedule = BusinessHoursSchedule.parse(
        'Seg: Fechado; Qui: 09:00 às 13:00; Dom: Fechado',
      )!;
      expect(
        schedule.nextEventAt(DateTime.utc(2026, 11, 2, 15))?.label,
        'Abre quinta-feira às 09h',
      );

      final mondayOnly = BusinessHoursSchedule.parse(
        'Seg: 08:00 às 12:00; Ter-Dom: Fechado',
      )!;
      expect(
        mondayOnly.nextEventAt(DateTime.utc(2026, 11, 2, 22))?.label,
        'Abre segunda-feira às 08h',
      );
    });

    test('describes overnight closing and opening in Brasília local dates', () {
      final schedule = BusinessHoursSchedule.parse(
        'Seg: 22:00 às 02:00; Ter: 09:00 às 18:00',
      )!;

      // Tuesday 02:30 UTC is Monday 23:30 in Brasília.
      expect(
        schedule.nextEventAt(DateTime.utc(2026, 11, 3, 2, 30))?.label,
        'Fecha amanhã às 02h',
      );
      // Tuesday 05:00 UTC is Tuesday 02:00 Brasília, after the overnight close.
      expect(
        schedule.nextEventAt(DateTime.utc(2026, 11, 3, 5))?.label,
        'Abre hoje às 09h',
      );
    });

    test('does not invent a next event for missing or invalid schedules', () {
      expect(
        BusinessHoursSchedule.parse('')?.nextEventAt(DateTime.now()),
        isNull,
      );
      expect(
        BusinessHoursSchedule.parse(
          'Atendimento conforme agendamento',
        )?.nextEventAt(DateTime.now()),
        isNull,
      );
      expect(
        BusinessHoursSchedule.parse(
          'Seg: Aberto',
        )?.nextEventAt(DateTime.utc(2026, 11, 2, 15)),
        isNull,
      );
      expect(
        BusinessHoursSchedule.parse(
          'Seg: Fechado; Ter: Fechado',
        )?.nextEventAt(DateTime.utc(2026, 11, 2, 15)),
        isNull,
      );
    });

    test(
      'keeps unspecified legacy days unknown instead of calling them closed',
      () {
        final schedule = BusinessHoursSchedule.parse('Seg-Sáb: 10h às 18h')!;

        expect(schedule.statusAt(DateTime.utc(2026, 11, 8, 15)), isNull);
      },
    );

    test('does not infer a current status from unrecognized free text', () {
      expect(
        BusinessHoursSchedule.parse('Atendimento conforme agendamento'),
        isNull,
      );
    });
  });

  testWidgets('admin selects days and opening state without typing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessHoursEditor(
              value: value,
              onChanged: (next) => value = next,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nenhum horário configurado.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('business-hours-configure')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('business-hours-state-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aberto').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('business-hours-open-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('business-hours-close-1')),
      findsOneWidget,
    );
    expect(value, contains('Seg: Aberto'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selector fits a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessHoursEditor(value: '', onChanged: (_) {}),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('business-hours-configure')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('public hours panel signals open using Brasília time', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessHoursInfo(
            hours: 'Seg-Sex: 09:00 às 18:00; Sáb: Fechado; Dom: Fechado',
            clock: () => DateTime.utc(2026, 11, 2, 15),
          ),
        ),
      ),
    );

    expect(find.text('Aberto agora'), findsOneWidget);
    expect(find.text('Horário de Brasília'), findsOneWidget);
    expect(find.text('Fecha hoje às 18h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile hours show the next known event across phone widths', (
    tester,
  ) async {
    for (final width in <double>[320, 360, 412]) {
      await tester.binding.setSurfaceSize(Size(width, 700));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: BusinessHoursInfo(
                hours: 'Seg: 09:00 às 18:00; Ter: 08:00 às 12:00',
                clock: () => DateTime.utc(2026, 11, 2, 22),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Abre amanhã às 08h'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
    await tester.binding.setSurfaceSize(null);
  });
}
