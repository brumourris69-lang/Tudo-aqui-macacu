import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tudo_aqui_macacu/features/events/utils/city_calendar_date.dart';

void main() {
  test('converts UTC instants to the Brasília calendar date', () {
    final timestamp = Timestamp.fromDate(DateTime.utc(2026, 11, 1, 2));

    expect(dateInBrasilia(timestamp), DateTime(2026, 10, 31, 23));
    expect(dateInBrasilia('2026-11-01T02:00:00Z'), DateTime(2026, 10, 31, 23));
  });

  test(
    'keeps date-only and timezone-free event dates as Brasília wall time',
    () {
      expect(dateInBrasilia('2026-11-01'), DateTime(2026, 11, 1));
      expect(
        dateInBrasilia('2026-11-01T18:30:00'),
        DateTime(2026, 11, 1, 18, 30),
      );
      expect(dateInBrasilia('01/11/2026 às 18h'), DateTime(2026, 11, 1));
      expect(dateInBrasilia('31/02/2026'), isNull);
    },
  );

  test('multi-day event occupies every date in its inclusive interval', () {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 11, 3);

    expect(eventEndDateInBrasilia({'endDate': '2026-11-03'}, start), end);
    expect(
      occursOnBrasiliaDay(start: start, end: end, day: DateTime(2026, 11, 2)),
      isTrue,
    );
    expect(
      occursOnBrasiliaDay(start: start, end: end, day: DateTime(2026, 11, 3)),
      isTrue,
    );
    expect(
      occursOnBrasiliaDay(start: start, end: end, day: DateTime(2026, 11, 4)),
      isFalse,
    );
    expect(eventEndDateInBrasilia({'endDate': '2026-10-31'}, start), start);
  });

  test('event stays active through its final Brasília day and end time', () {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 11, 3);

    expect(
      hasEventEndedInBrasilia(
        start: start,
        end: end,
        endTime: '22:00',
        now: DateTime(2026, 11, 3, 21, 59),
      ),
      isFalse,
    );
    expect(
      hasEventEndedInBrasilia(
        start: start,
        end: end,
        endTime: '22:00',
        now: DateTime(2026, 11, 3, 22),
      ),
      isTrue,
    );
  });
}
