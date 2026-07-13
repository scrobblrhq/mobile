import 'package:flutter/material.dart';

import '../../api/models.dart';

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

const _weekdayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// GitHub-style activity heatmap: one column per week (Monday-first), one
/// cell per day, intensity scaled against the busiest day of the year.
/// Days are UTC to match the server's daily buckets. Tapping a cell shows
/// its date and count below the grid.
class ActivityHeatmap extends StatefulWidget {
  const ActivityHeatmap({super.key, required this.days});

  /// Sparse day → count data (days without scrobbles are absent).
  final List<ActivityDay> days;

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  static const double _cell = 11;
  static const double _gap = 3;
  static const double _slot = _cell + _gap;

  DateTime? _selected;

  static DateTime _dateOnly(DateTime d) {
    final utc = d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  Color _cellColor(ColorScheme scheme, int count, int max) {
    if (count <= 0) return scheme.surfaceContainerHighest;
    final bucket = max <= 0 ? 1.0 : (count / max).clamp(0.0, 1.0);
    if (bucket <= 0.25) return scheme.primary.withValues(alpha: 0.3);
    if (bucket <= 0.5) return scheme.primary.withValues(alpha: 0.5);
    if (bucket <= 0.75) return scheme.primary.withValues(alpha: 0.75);
    return scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final counts = <DateTime, int>{
      for (final d in widget.days) _dateOnly(d.day): d.scrobbleCount,
    };
    final max = counts.values.fold(0, (a, b) => a > b ? a : b);
    final total = counts.values.fold(0, (a, b) => a + b);

    final today = _dateOnly(DateTime.now());
    var start = today.subtract(const Duration(days: 364));
    // Align back to Monday so every column is a full week.
    start = start.subtract(Duration(days: start.weekday - 1));

    final weekStarts = <DateTime>[];
    for (var w = start; !w.isAfter(today); w = w.add(const Duration(days: 7))) {
      weekStarts.add(w);
    }

    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$total scrobbles in the last year',
          style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Weekday gutter (Mon/Wed/Fri), aligned with the grid rows.
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                children: [
                  for (var row = 0; row < 7; row++)
                    SizedBox(
                      height: _slot,
                      width: 28,
                      child:
                          row.isEven
                              ? Text(
                                _weekdayAbbr[row],
                                style: text.labelSmall?.copyWith(
                                  color: scheme.outline,
                                ),
                              )
                              : null,
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Start scrolled to the most recent week.
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month labels where the month changes between columns.
                    Row(
                      children: [
                        for (var i = 0; i < weekStarts.length; i++)
                          SizedBox(
                            width: _slot,
                            height: 16,
                            child:
                                i == 0 ||
                                        weekStarts[i].month !=
                                            weekStarts[i - 1].month
                                    ? Text(
                                      _monthAbbr[weekStarts[i].month - 1],
                                      softWrap: false,
                                      overflow: TextOverflow.visible,
                                      style: text.labelSmall?.copyWith(
                                        color: scheme.outline,
                                      ),
                                    )
                                    : null,
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        for (final week in weekStarts)
                          Column(
                            children: [
                              for (var row = 0; row < 7; row++)
                                _buildCell(
                                  scheme,
                                  week.add(Duration(days: row)),
                                  today,
                                  counts,
                                  max,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (selected != null)
              Expanded(
                child: Text(
                  '${counts[selected] ?? 0} scrobbles · '
                  '${_weekdayAbbr[selected.weekday - 1]} '
                  '${selected.day} ${_monthAbbr[selected.month - 1]}',
                  style: text.labelMedium,
                ),
              )
            else
              const Spacer(),
            Text(
              'Less',
              style: text.labelSmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(width: 4),
            for (final level in [0, 1, 2, 3, 4]) ...[
              Container(
                width: _cell,
                height: _cell,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: _cellColor(scheme, level == 0 ? 0 : level, 4),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Text(
              'More',
              style: text.labelSmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCell(
    ColorScheme scheme,
    DateTime day,
    DateTime today,
    Map<DateTime, int> counts,
    int max,
  ) {
    if (day.isAfter(today)) {
      return const SizedBox(width: _slot, height: _slot);
    }
    final selected = _selected == day;
    return GestureDetector(
      onTap: () => setState(() => _selected = selected ? null : day),
      child: Container(
        width: _cell,
        height: _cell,
        margin: const EdgeInsets.only(right: _gap, bottom: _gap),
        decoration: BoxDecoration(
          color: _cellColor(scheme, counts[day] ?? 0, max),
          borderRadius: BorderRadius.circular(2.5),
          border:
              selected ? Border.all(color: scheme.onSurface, width: 1.5) : null,
        ),
      ),
    );
  }
}
