import 'package:flutter/material.dart';

import '../utils/city_calendar_date.dart';

const List<String> _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];
const List<String> _weekdays = [
  'seg',
  'ter',
  'qua',
  'qui',
  'sex',
  'sáb',
  'dom',
];

class CityMonthCalendar extends StatelessWidget {
  const CityMonthCalendar({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.hasEvents,
    required this.onDateSelected,
    required this.onMonthChanged,
    required this.onToday,
  });

  final DateTime month;
  final DateTime? selectedDate;
  final bool Function(DateTime day) hasEvents;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<int> onMonthChanged;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final leading = first.weekday - DateTime.monday;
    final rowCount = ((leading + days) / 7).ceil();
    final today = currentBrasiliaDateTime();
    final title = '${_months[first.month - 1]} de ${first.year}';
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('city-calendar-previous'),
                  tooltip: 'Mês anterior',
                  onPressed: () => onMonthChanged(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('city-calendar-next'),
                  tooltip: 'Próximo mês',
                  onPressed: () => onMonthChanged(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                TextButton(onPressed: onToday, child: const Text('Hoje')),
              ],
            ),
            Row(
              children: [
                for (final weekday in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekday,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var row = 0; row < rowCount; row++)
              Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(
                      child: _dayCell(
                        context,
                        dayNumber: row * 7 + column - leading + 1,
                        daysInMonth: days,
                        selectedDate: selectedDate,
                        today: today,
                        hasEvents: hasEvents,
                        onDateSelected: onDateSelected,
                        scheme: scheme,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(
    BuildContext context, {
    required int dayNumber,
    required int daysInMonth,
    required DateTime? selectedDate,
    required DateTime today,
    required bool Function(DateTime) hasEvents,
    required ValueChanged<DateTime> onDateSelected,
    required ColorScheme scheme,
  }) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 44);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final selected =
        selectedDate != null && DateUtils.isSameDay(selectedDate, day);
    final isToday = DateUtils.isSameDay(today, day);
    final marked = hasEvents(day);
    final keyDate =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${day.day} ${_months[day.month - 1]}${marked ? ', há eventos' : ''}',
      child: InkWell(
        key: ValueKey('calendar-day-$keyDate'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => onDateSelected(day),
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : null,
                  borderRadius: BorderRadius.circular(10),
                  border: isToday && !selected
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '$dayNumber',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected ? scheme.onPrimary : null,
                    fontWeight: selected || isToday
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                height: 5,
                child: marked
                    ? Container(
                        key: ValueKey('calendar-dot-$keyDate'),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : scheme.secondary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
