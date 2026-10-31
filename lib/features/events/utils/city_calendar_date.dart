import 'package:cloud_firestore/cloud_firestore.dart';

const Duration _brasiliaOffset = Duration(hours: -3);

/// Converts instants to Brasília wall time (UTC-03:00) and keeps timezone-free
/// event values as the local calendar values entered by the administrator.
DateTime? dateInBrasilia(Object? value) {
  if (value is Timestamp) return _instantInBrasilia(value.toDate());
  if (value is DateTime) {
    return value.isUtc ? _instantInBrasilia(value) : _wallDate(value);
  }
  if (value is Map && value.length == 1 && value['_publicTimestamp'] is List) {
    final parts = value['_publicTimestamp'] as List;
    if (parts.length == 2 && parts.every((part) => part is int)) {
      final seconds = parts[0] as int;
      final nanos = parts[1] as int;
      if (nanos < 0 || nanos >= 1000000000) return null;
      return _instantInBrasilia(
        DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + nanos ~/ 1000000,
          isUtc: true,
        ),
      );
    }
    return null;
  }
  if (value is! String || value.trim().isEmpty) return null;

  final raw = value.trim();
  final isoDate = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[Tt ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(.*))?$',
  ).firstMatch(raw);
  if (isoDate != null) {
    final year = int.parse(isoDate.group(1)!);
    final month = int.parse(isoDate.group(2)!);
    final day = int.parse(isoDate.group(3)!);
    final hour = int.tryParse(isoDate.group(4) ?? '') ?? 0;
    final minute = int.tryParse(isoDate.group(5) ?? '') ?? 0;
    final second = int.tryParse(isoDate.group(6) ?? '') ?? 0;
    final milliseconds =
        int.tryParse('${isoDate.group(7) ?? ''}000'.substring(0, 3)) ?? 0;
    final wall = DateTime(year, month, day, hour, minute, second, milliseconds);
    if (!_validComponents(wall, year, month, day, hour, minute, second)) {
      return null;
    }
    final zone = (isoDate.group(8) ?? '').trim();
    if (zone.isEmpty) return wall;
    // DateTime's ISO parser handles Z and signed offsets; reject unsupported
    // trailing content instead of silently changing the intended date.
    if (!RegExp(r'^(?:Z|z|[+-]\d{2}:?\d{2})$').hasMatch(zone)) return null;
    final instant = DateTime.tryParse(raw);
    return instant == null ? null : _instantInBrasilia(instant);
  }

  final legacy = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})(?:\s+às\s+(\d{1,2})(?::(\d{2}))?h?)?$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (legacy == null) return null;
  final day = int.parse(legacy.group(1)!);
  final month = int.parse(legacy.group(2)!);
  var year = int.parse(legacy.group(3)!);
  if (year < 100) year += 2000;
  final result = DateTime(year, month, day);
  return _validComponents(result, year, month, day, 0, 0, 0) ? result : null;
}

DateTime _instantInBrasilia(DateTime value) {
  final wall = value.toUtc().add(_brasiliaOffset);
  return DateTime(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
    wall.millisecond,
    wall.microsecond,
  );
}

DateTime _wallDate(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);

bool _validComponents(
  DateTime value,
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
) =>
    value.year == year &&
    value.month == month &&
    value.day == day &&
    hour >= 0 &&
    hour <= 23 &&
    minute >= 0 &&
    minute <= 59 &&
    second >= 0 &&
    second <= 59;

DateTime eventEndDateInBrasilia(Map<String, dynamic> event, DateTime start) {
  final parsed = dateInBrasilia(event['endDate']);
  final end = DateTime(
    parsed?.year ?? start.year,
    parsed?.month ?? start.month,
    parsed?.day ?? start.day,
  );
  final startDay = DateTime(start.year, start.month, start.day);
  return end.isBefore(startDay) ? startDay : end;
}

bool occursOnBrasiliaDay({
  required DateTime start,
  required DateTime end,
  required DateTime day,
}) {
  final date = DateTime(day.year, day.month, day.day);
  final first = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  return !date.isBefore(first) && !date.isAfter(last);
}

bool hasEventEndedInBrasilia({
  required DateTime start,
  required DateTime end,
  required String endTime,
  required DateTime now,
}) {
  final lastDay = DateTime(end.year, end.month, end.day);
  final current = now.isUtc ? _instantInBrasilia(now) : _wallDate(now);
  final today = DateTime(current.year, current.month, current.day);
  if (lastDay.isBefore(today)) return true;
  if (lastDay.isAfter(today)) return false;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(endTime.trim());
  if (match == null) return false;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return false;
  return !current.isBefore(
    DateTime(today.year, today.month, today.day, hour, minute),
  );
}

DateTime currentBrasiliaDateTime() =>
    _instantInBrasilia(DateTime.now().toUtc());
