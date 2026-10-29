import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/daily_models.dart';

/// How one day of a [MonthCalendar] looks and whether it can be tapped.
class DayLook {
  const DayLook({
    this.fill,
    this.ink,
    this.band = false,
    this.bandStart = false,
    this.bandEnd = false,
    this.strike = false,
    this.enabled = true,
    this.label,
  });

  /// A filled disc behind the number (a chosen day, a booked night).
  final Color? fill;
  final Color? ink;

  /// Part of a chosen range: a tinted band joins it to its neighbours.
  final bool band;
  final bool bandStart;
  final bool bandEnd;

  /// Crossed out: taken, or closed by the owner.
  final bool strike;
  final bool enabled;

  /// Read out after the date ("Not available").
  final String? label;
}

/// One month as a seven-column grid, in the reader's week order and
/// direction, with month arrows. The days' looks come from [look]; taps go
/// to [onTap]. Used for picking a stay and for an owner's availability.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.onMonth,
    required this.look,
    required this.onTap,
    this.firstMonth,
    this.lastMonth,
  });

  /// Any day in the month shown.
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final DayLook Function(DateTime day) look;
  final ValueChanged<DateTime> onTap;
  final DateTime? firstMonth;
  final DateTime? lastMonth;

  static DateTime _first(DateTime d) => DateTime(d.year, d.month);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final lang = context.lang;
    final ml = MaterialLocalizations.of(context);
    final first = _first(month);
    final canBack = firstMonth == null || first.isAfter(_first(firstMonth!));
    final canForward = lastMonth == null || first.isBefore(_first(lastMonth!));
    final startDay = ml.firstDayOfWeekIndex; // 0 = Sunday
    final lead = (first.weekday % 7 - startDay + 7) % 7;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) DateTime(first.year, first.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final today = dayOnly(DateTime.now());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l.previousMonth,
              onPressed: canBack ? () => onMonth(DateTime(first.year, first.month - 1)) : null,
              icon: Icon(rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                Fmt.month(first, lang: lang),
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
            ),
            IconButton(
              tooltip: l.nextMonth,
              onPressed: canForward ? () => onMonth(DateTime(first.year, first.month + 1)) : null,
              icon: Icon(rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    ml.narrowWeekdays[(startDay + i) % 7],
                    textAlign: TextAlign.center,
                    style: context.text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.xxs),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: cells[row * 7 + col] == null
                      ? const AspectRatio(aspectRatio: 1, child: SizedBox())
                      : _Day(
                          day: cells[row * 7 + col]!,
                          look: look(cells[row * 7 + col]!),
                          today: cells[row * 7 + col] == today,
                          onTap: onTap,
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day, required this.look, required this.today, required this.onTap});
  final DateTime day;
  final DayLook look;
  final bool today;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    final tint = c.emerald.withValues(alpha: 0.14);
    final ink = look.ink ?? (look.enabled ? c.ink : c.inkFaint);
    final semantics = [Fmt.night(day, lang: lang), ?look.label].join(', ');
    return AspectRatio(
      aspectRatio: 1,
      child: Semantics(
        button: look.enabled,
        enabled: look.enabled,
        selected: look.fill != null,
        label: semantics,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: look.enabled
              ? () {
                  unawaited(HapticFeedback.selectionClick());
                  onTap(day);
                }
              : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The band joining a range runs edge to edge, cut in half at its
              // two ends so it starts and stops at the discs' centres.
              if (look.band)
                Positioned.fill(
                  top: 4,
                  bottom: 4,
                  child: Row(
                    children: [
                      Expanded(child: ColoredBox(color: look.bandStart ? Colors.transparent : tint)),
                      Expanded(child: ColoredBox(color: look.bandEnd ? Colors.transparent : tint)),
                    ],
                  ),
                ),
              if (look.fill != null)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: look.fill, shape: BoxShape.circle),
                    child: const SizedBox.expand(),
                  ),
                ),
              Text(
                '${day.day}',
                style: context.text.bodyMedium?.copyWith(
                  color: ink,
                  fontWeight: today ? FontWeight.w700 : null,
                  decoration: look.strike ? TextDecoration.lineThrough : null,
                  decorationColor: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
