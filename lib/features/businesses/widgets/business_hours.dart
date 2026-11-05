import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mini_label.dart';

enum BusinessOpeningStatus { open, closed }

@immutable
class BusinessHoursNextEvent {
  const BusinessHoursNextEvent({
    required this.nextStatus,
    required this.brasiliaWallTime,
    required this.dayOffset,
  });

  final BusinessOpeningStatus nextStatus;

  /// A UTC DateTime whose fields represent the Brasília wall-clock time.
  final DateTime brasiliaWallTime;
  final int dayOffset;

  String get label {
    final dayLabel = switch (dayOffset) {
      0 => 'hoje',
      1 => 'amanhã',
      _ => switch (brasiliaWallTime.weekday) {
        DateTime.monday => 'segunda-feira',
        DateTime.tuesday => 'terça-feira',
        DateTime.wednesday => 'quarta-feira',
        DateTime.thursday => 'quinta-feira',
        DateTime.friday => 'sexta-feira',
        DateTime.saturday => 'sábado',
        DateTime.sunday => 'domingo',
        _ => '',
      },
    };
    final hour = brasiliaWallTime.hour.toString().padLeft(2, '0');
    final minute = brasiliaWallTime.minute;
    final timeLabel = minute == 0
        ? '${hour}h'
        : '$hour:${minute.toString().padLeft(2, '0')}';
    final verb = nextStatus == BusinessOpeningStatus.open ? 'Abre' : 'Fecha';
    return '$verb $dayLabel às $timeLabel';
  }
}

enum BusinessDayState { unspecified, closed, open }

@immutable
class BusinessDayHours {
  const BusinessDayHours({
    required this.state,
    this.opensAtMinute,
    this.closesAtMinute,
  });

  final BusinessDayState state;
  final int? opensAtMinute;
  final int? closesAtMinute;

  bool get isOpen => state == BusinessDayState.open;

  @override
  bool operator ==(Object other) =>
      other is BusinessDayHours &&
      other.state == state &&
      other.opensAtMinute == opensAtMinute &&
      other.closesAtMinute == closesAtMinute;

  @override
  int get hashCode => Object.hash(state, opensAtMinute, closesAtMinute);
}

@immutable
class BusinessHoursSchedule {
  BusinessHoursSchedule(Map<int, BusinessDayHours> days)
    : days = Map.unmodifiable(days);

  final Map<int, BusinessDayHours> days;

  static const _dayNames = <int, String>{
    DateTime.monday: 'Seg',
    DateTime.tuesday: 'Ter',
    DateTime.wednesday: 'Qua',
    DateTime.thursday: 'Qui',
    DateTime.friday: 'Sex',
    DateTime.saturday: 'Sáb',
    DateTime.sunday: 'Dom',
  };

  static final _dayToken = RegExp(
    r'segunda|seg|terca|ter|quarta|qua|quinta|qui|sexta|sex|sabado|sab|domingo|dom',
  );
  static final _timeRange = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(?:h|hs)?\s*(?:as|a|ate|[-–—])\s*(\d{1,2})(?::(\d{2}))?\s*(?:h|hs)?',
  );

  factory BusinessHoursSchedule.empty() => BusinessHoursSchedule(const {});

  static BusinessHoursSchedule? parse(String value) {
    final normalized = _normalize(value.trim());
    if (normalized.isEmpty) return null;

    final parsed = <int, BusinessDayHours>{};
    for (final rawClause in normalized.split(RegExp(r'[|;\n]+'))) {
      final clause = rawClause.trim();
      if (clause.isEmpty) continue;
      final separator = clause.indexOf(':');
      if (separator <= 0) return null;
      final dayExpression = clause.substring(0, separator).trim();
      final valueExpression = clause.substring(separator + 1).trim();
      final dayNumbers = _daysIn(dayExpression);
      if (dayNumbers.isEmpty) return null;

      final dayValue = _parseValue(valueExpression);
      if (dayValue == null) return null;
      for (final day in dayNumbers) {
        if (parsed.containsKey(day)) return null;
        parsed[day] = dayValue;
      }
    }
    return parsed.isEmpty ? null : BusinessHoursSchedule(parsed);
  }

  static BusinessDayHours? _parseValue(String value) {
    if (value.contains('nao informado') || value.contains('nao definido')) {
      return const BusinessDayHours(state: BusinessDayState.unspecified);
    }
    if (value.contains('fechado')) {
      return const BusinessDayHours(state: BusinessDayState.closed);
    }
    final match = _timeRange.firstMatch(value);
    if (match != null) {
      final start = _minute(match.group(1), match.group(2));
      final end = _minute(match.group(3), match.group(4));
      // A closing time earlier than opening means this schedule crosses
      // midnight. Equal times are ambiguous and are not treated as 24 hours.
      if (start == null || end == null || end == start) return null;
      return BusinessDayHours(
        state: BusinessDayState.open,
        opensAtMinute: start,
        closesAtMinute: end,
      );
    }
    if (value == 'aberto') {
      return const BusinessDayHours(state: BusinessDayState.open);
    }
    return null;
  }

  static int? _minute(String? hourText, String? minuteText) {
    final hour = int.tryParse(hourText ?? '');
    final minute = int.tryParse(minuteText ?? '0');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static List<int> _daysIn(String expression) {
    final matches = _dayToken.allMatches(expression).toList();
    if (matches.isEmpty) return const [];
    final days = matches.map((match) => _dayNumber(match.group(0)!)).toList();
    if (days.any((day) => day == null)) return const [];
    final numbers = days.cast<int>();
    final isRange = RegExp(r'[-–—]|\ba\b|\bate\b').hasMatch(expression);
    if (isRange && numbers.length == 2) {
      final result = <int>[];
      var day = numbers.first;
      for (var count = 0; count < 7; count++) {
        result.add(day);
        if (day == numbers.last) return result;
        day = day == DateTime.sunday ? DateTime.monday : day + 1;
      }
      return const [];
    }
    return numbers.toSet().toList();
  }

  static int? _dayNumber(String token) => switch (token) {
    'segunda' || 'seg' => DateTime.monday,
    'terca' || 'ter' => DateTime.tuesday,
    'quarta' || 'qua' => DateTime.wednesday,
    'quinta' || 'qui' => DateTime.thursday,
    'sexta' || 'sex' => DateTime.friday,
    'sabado' || 'sab' => DateTime.saturday,
    'domingo' || 'dom' => DateTime.sunday,
    _ => null,
  };

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u');

  String toStorage() {
    if (days.isEmpty ||
        days.values.every((day) => day.state == BusinessDayState.unspecified)) {
      return '';
    }
    final groups = <({int start, int end, BusinessDayHours hours})>[];
    for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
      final hours =
          days[day] ??
          const BusinessDayHours(state: BusinessDayState.unspecified);
      if (groups.isNotEmpty &&
          groups.last.end == day - 1 &&
          groups.last.hours == hours) {
        groups[groups.length - 1] = (
          start: groups.last.start,
          end: day,
          hours: hours,
        );
      } else {
        groups.add((start: day, end: day, hours: hours));
      }
    }
    return groups
        .map(
          (group) =>
              '${_dayNames[group.start]}${group.start == group.end ? '' : '–${_dayNames[group.end]}'}: ${_valueText(group.hours)}',
        )
        .join('; ');
  }

  static String _valueText(BusinessDayHours hours) => switch (hours.state) {
    BusinessDayState.unspecified => 'Não informado',
    BusinessDayState.closed => 'Fechado',
    BusinessDayState.open
        when hours.opensAtMinute != null && hours.closesAtMinute != null =>
      '${_formatMinute(hours.opensAtMinute!)} às ${_formatMinute(hours.closesAtMinute!)}',
    BusinessDayState.open => 'Aberto',
  };

  static String _formatMinute(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  BusinessOpeningStatus? statusAt(DateTime instant) {
    // Macacu follows Brasília time (UTC-03:00). Brazilian daylight saving is
    // not in effect; using the fixed offset also avoids the phone timezone.
    final brasilia = _toBrasiliaWallTime(instant);
    final minute = brasilia.hour * 60 + brasilia.minute;
    final previousWeekday = brasilia.weekday == DateTime.monday
        ? DateTime.sunday
        : brasilia.weekday - 1;
    final previous = days[previousWeekday];
    final previousOpens = previous?.opensAtMinute;
    final previousCloses = previous?.closesAtMinute;
    if (previous?.state == BusinessDayState.open &&
        previousOpens != null &&
        previousCloses != null &&
        previousOpens > previousCloses &&
        minute < previousCloses) {
      return BusinessOpeningStatus.open;
    }

    final day = days[brasilia.weekday];
    if (day == null || day.state == BusinessDayState.unspecified) return null;
    if (day.state == BusinessDayState.closed) {
      return BusinessOpeningStatus.closed;
    }
    final opens = day.opensAtMinute;
    final closes = day.closesAtMinute;
    if (opens == null || closes == null) return null;
    final isOpen = opens < closes
        ? minute >= opens && minute < closes
        : minute >= opens;
    return isOpen ? BusinessOpeningStatus.open : BusinessOpeningStatus.closed;
  }

  BusinessHoursNextEvent? nextEventAt(DateTime instant) {
    final brasilia = _toBrasiliaWallTime(instant);
    final status = statusAt(instant);
    if (status == null) return null;

    if (status == BusinessOpeningStatus.open) {
      final minute = brasilia.hour * 60 + brasilia.minute;
      final previousWeekday = _previousWeekday(brasilia.weekday);
      final previous = days[previousWeekday];
      final previousOpens = previous?.opensAtMinute;
      final previousCloses = previous?.closesAtMinute;
      final isOvernightCarryover =
          previous?.state == BusinessDayState.open &&
          previousOpens != null &&
          previousCloses != null &&
          previousOpens > previousCloses &&
          minute < previousCloses;
      if (isOvernightCarryover) {
        return _eventAt(
          BusinessOpeningStatus.closed,
          brasilia,
          previousCloses,
          dayOffset: 0,
        );
      }

      final day = days[brasilia.weekday];
      final opens = day?.opensAtMinute;
      final closes = day?.closesAtMinute;
      if (opens == null || closes == null) return null;
      final crossesMidnight = opens > closes;
      return _eventAt(
        BusinessOpeningStatus.closed,
        brasilia,
        closes,
        dayOffset: crossesMidnight ? 1 : 0,
      );
    }

    final today = DateTime.utc(brasilia.year, brasilia.month, brasilia.day);
    for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final day = days[date.weekday];
      final opens = day?.opensAtMinute;
      final closes = day?.closesAtMinute;
      if (day?.state != BusinessDayState.open ||
          opens == null ||
          closes == null) {
        continue;
      }
      final candidate = DateTime.utc(
        date.year,
        date.month,
        date.day,
        opens ~/ 60,
        opens % 60,
      );
      if (candidate.isAfter(brasilia)) {
        return _createEvent(BusinessOpeningStatus.open, candidate, brasilia);
      }
    }
    return null;
  }

  BusinessHoursNextEvent _eventAt(
    BusinessOpeningStatus status,
    DateTime today,
    int minuteOfDay, {
    required int dayOffset,
  }) => _createEvent(
    status,
    DateTime.utc(
      today.year,
      today.month,
      today.day + dayOffset,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    ),
    today,
  );

  BusinessHoursNextEvent _createEvent(
    BusinessOpeningStatus status,
    DateTime candidate,
    DateTime now,
  ) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final eventDay = DateTime.utc(
      candidate.year,
      candidate.month,
      candidate.day,
    );
    return BusinessHoursNextEvent(
      nextStatus: status,
      brasiliaWallTime: candidate,
      dayOffset: eventDay.difference(today).inDays,
    );
  }

  static DateTime _toBrasiliaWallTime(DateTime instant) =>
      instant.toUtc().subtract(const Duration(hours: 3));

  static int _previousWeekday(int weekday) =>
      weekday == DateTime.monday ? DateTime.sunday : weekday - 1;

  BusinessHoursSchedule withDay(int weekday, BusinessDayHours hours) =>
      BusinessHoursSchedule({...days, weekday: hours});
}

class BusinessHoursEditor extends StatefulWidget {
  const BusinessHoursEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<BusinessHoursEditor> createState() => _BusinessHoursEditorState();
}

class _BusinessHoursEditorState extends State<BusinessHoursEditor> {
  late BusinessHoursSchedule? schedule;
  bool replacingLegacy = false;

  @override
  void initState() {
    super.initState();
    schedule = BusinessHoursSchedule.parse(widget.value);
  }

  @override
  void didUpdateWidget(covariant BusinessHoursEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      schedule = BusinessHoursSchedule.parse(widget.value);
      replacingLegacy = false;
    }
  }

  void _setDay(int weekday, BusinessDayState state) {
    final previous = schedule?.days[weekday];
    final next = switch (state) {
      BusinessDayState.unspecified => const BusinessDayHours(
        state: BusinessDayState.unspecified,
      ),
      BusinessDayState.closed => const BusinessDayHours(
        state: BusinessDayState.closed,
      ),
      BusinessDayState.open => BusinessDayHours(
        state: BusinessDayState.open,
        opensAtMinute: previous?.opensAtMinute,
        closesAtMinute: previous?.closesAtMinute,
      ),
    };
    setState(
      () => schedule = (schedule ?? BusinessHoursSchedule.empty()).withDay(
        weekday,
        next,
      ),
    );
    widget.onChanged(schedule!.toStorage());
  }

  Future<void> _pickTime(int weekday, {required bool opening}) async {
    final day = schedule?.days[weekday];
    final currentMinute = opening ? day?.opensAtMinute : day?.closesAtMinute;
    final initial = currentMinute == null
        ? TimeOfDay(hour: opening ? 9 : 18, minute: 0)
        : TimeOfDay(hour: currentMinute ~/ 60, minute: currentMinute % 60);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final newMinute = picked.hour * 60 + picked.minute;
    final start = opening ? newMinute : day?.opensAtMinute;
    final end = opening ? day?.closesAtMinute : newMinute;
    if (start != null && end != null && end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O encerramento precisa ser depois da abertura.'),
        ),
      );
      return;
    }
    final updated = BusinessDayHours(
      state: BusinessDayState.open,
      opensAtMinute: start,
      closesAtMinute: end,
    );
    setState(
      () => schedule = (schedule ?? BusinessHoursSchedule.empty()).withDay(
        weekday,
        updated,
      ),
    );
    widget.onChanged(schedule!.toStorage());
  }

  @override
  Widget build(BuildContext context) {
    final value = schedule;
    if (value == null && !replacingLegacy) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Horários de funcionamento',
          helperText: 'Configure os dias e horários sem precisar digitar.',
          border: OutlineInputBorder(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.value.isEmpty
                  ? 'Nenhum horário configurado.'
                  : widget.value,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('business-hours-configure'),
                onPressed: widget.enabled
                    ? () => setState(() {
                        replacingLegacy = true;
                        schedule = BusinessHoursSchedule.empty();
                      })
                    : null,
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Configurar por seleção'),
              ),
            ),
          ],
        ),
      );
    }

    final activeSchedule = value ?? BusinessHoursSchedule.empty();
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Horários de funcionamento',
        helperText: 'Escolha o estado de cada dia e selecione os horários.',
        border: OutlineInputBorder(),
      ),
      child: Column(
        children: [
          for (final day in <int>[
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
            DateTime.saturday,
            DateTime.sunday,
          ])
            _dayRow(activeSchedule, day),
        ],
      ),
    );
  }

  Widget _dayRow(BusinessHoursSchedule current, int weekday) {
    final names = const {
      DateTime.monday: 'Segunda',
      DateTime.tuesday: 'Terça',
      DateTime.wednesday: 'Quarta',
      DateTime.thursday: 'Quinta',
      DateTime.friday: 'Sexta',
      DateTime.saturday: 'Sábado',
      DateTime.sunday: 'Domingo',
    };
    final hours = current.days[weekday];
    final state = hours?.state ?? BusinessDayState.unspecified;
    final isOpen = state == BusinessDayState.open;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 82, child: Text(names[weekday]!)),
              Expanded(
                child: DropdownButtonFormField<BusinessDayState>(
                  key: ValueKey('business-hours-state-$weekday'),
                  initialValue: state,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: BusinessDayState.unspecified,
                      child: Text('Não informado'),
                    ),
                    DropdownMenuItem(
                      value: BusinessDayState.closed,
                      child: Text('Fechado'),
                    ),
                    DropdownMenuItem(
                      value: BusinessDayState.open,
                      child: Text('Aberto'),
                    ),
                  ],
                  onChanged: widget.enabled
                      ? (next) {
                          if (next != null) _setDay(weekday, next);
                        }
                      : null,
                ),
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('business-hours-open-$weekday'),
                  onPressed: widget.enabled
                      ? () => _pickTime(weekday, opening: true)
                      : null,
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: Text(
                    hours?.opensAtMinute == null
                        ? 'Abertura'
                        : BusinessHoursSchedule._formatMinute(
                            hours!.opensAtMinute!,
                          ),
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey('business-hours-close-$weekday'),
                  onPressed: widget.enabled
                      ? () => _pickTime(weekday, opening: false)
                      : null,
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: Text(
                    hours?.closesAtMinute == null
                        ? 'Encerramento'
                        : BusinessHoursSchedule._formatMinute(
                            hours!.closesAtMinute!,
                          ),
                  ),
                ),
              ],
            ),
            if (hours?.opensAtMinute == null || hours?.closesAtMinute == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Selecione abertura e encerramento para calcular o status.',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class BusinessHoursInfo extends StatefulWidget {
  const BusinessHoursInfo({
    super.key,
    required this.hours,
    this.fallbackSpecified = false,
    this.fallbackOpen = false,
    this.clock,
  });

  final String hours;
  final bool fallbackSpecified;
  final bool fallbackOpen;
  final DateTime Function()? clock;

  @override
  State<BusinessHoursInfo> createState() => _BusinessHoursInfoState();
}

class BusinessOpeningStatusBadge extends StatelessWidget {
  const BusinessOpeningStatusBadge({
    super.key,
    required this.hours,
    required this.fallbackSpecified,
    required this.fallbackOpen,
    this.clock,
  });

  final String hours;
  final bool fallbackSpecified;
  final bool fallbackOpen;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final instant = clock?.call() ?? DateTime.now();
    final schedule = BusinessHoursSchedule.parse(hours);
    final status = schedule?.statusAt(instant);
    if (schedule != null && status == null) return const SizedBox.shrink();
    if (status == null && !fallbackSpecified) {
      return const SizedBox.shrink();
    }
    final isOpen =
        status == BusinessOpeningStatus.open ||
        (status == null && fallbackOpen);
    final nextEvent = status == null ? null : schedule?.nextEventAt(instant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MiniLabel(
          text: status == null
              ? (isOpen
                    ? 'Status informado: aberto'
                    : 'Status informado: fechado')
              : (isOpen ? 'ABERTO AGORA' : 'FECHADO AGORA'),
          color: isOpen ? const Color(0xFF188038) : AppColors.muted,
        ),
        if (nextEvent != null) ...[
          const SizedBox(height: 2),
          Text(
            nextEvent.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9,
              height: 1,
              color: nextEvent.nextStatus == BusinessOpeningStatus.open
                  ? AppColors.ocean
                  : AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _BusinessHoursInfoState extends State<BusinessHoursInfo> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schedule = BusinessHoursSchedule.parse(widget.hours);
    final instant = widget.clock?.call() ?? DateTime.now();
    final openingStatus = schedule?.statusAt(instant);
    final nextEvent = openingStatus == null
        ? null
        : schedule?.nextEventAt(instant);
    final showLegacy = schedule == null && widget.fallbackSpecified;
    final isOpen =
        openingStatus == BusinessOpeningStatus.open ||
        (showLegacy && widget.fallbackOpen);
    final color = isOpen ? const Color(0xFF188038) : AppColors.muted;
    return Container(
      key: const ValueKey('business-hours-info'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.ocean.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Horários',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (openingStatus != null || showLegacy)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    openingStatus == null
                        ? (isOpen
                              ? 'Status informado: aberto'
                              : 'Status informado: fechado')
                        : (isOpen ? 'Aberto agora' : 'Fechado agora'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(widget.hours, style: Theme.of(context).textTheme.bodyMedium),
          if (nextEvent != null) ...[
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: nextEvent.nextStatus == BusinessOpeningStatus.open
                      ? AppColors.ocean
                      : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nextEvent.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 3),
          Text(
            'Horário de Brasília',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
