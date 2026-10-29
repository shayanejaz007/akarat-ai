import 'package:material_ui/material_ui.dart';

import '../../shared/models/daily_models.dart';
import 'month_calendar.dart';

/// Choosing a stay on a calendar: the first tap is check-in, the second
/// check-out; tapping before check-in, or again once both are set, starts
/// over. A night someone already has can never start a stay, and no stay can
/// run through one, but it can be the morning someone leaves.
class StayPick {
  const StayPick({this.checkIn, this.checkOut, this.crossedTaken = false});

  final DateTime? checkIn;
  final DateTime? checkOut;

  /// The last tap would have run the stay through a taken night.
  final bool crossedTaken;

  bool get complete => checkIn != null && checkOut != null;
  int get nights => complete ? nightsBetween(checkIn!, checkOut!) : 0;

  StayPick tap(DateTime day, {Set<DateTime> taken = const {}}) {
    final d = dayOnly(day);
    if (checkIn == null || checkOut != null || !d.isAfter(checkIn!)) {
      return taken.contains(d) ? this : StayPick(checkIn: d);
    }
    for (var n = checkIn!; n.isBefore(d); n = DateTime(n.year, n.month, n.day + 1)) {
      if (taken.contains(n)) {
        return StayPick(checkIn: taken.contains(d) ? null : d, crossedTaken: true);
      }
    }
    return StayPick(checkIn: checkIn, checkOut: d);
  }

  /// How [day] looks on the calendar for this pick.
  DayLook look(
    DateTime day, {
    required DateTime today,
    required Color accent,
    required Color onAccent,
    Set<DateTime> taken = const {},
    String? takenLabel,
  }) {
    final d = dayOnly(day);
    final past = d.isBefore(today);
    final isTaken = taken.contains(d);
    // A taken night is still a valid check-out, the morning someone leaves.
    final asCheckOut = checkIn != null && checkOut == null && d.isAfter(checkIn!);
    final enabled = !past && (!isTaken || asCheckOut);
    final edge = d == checkIn || d == checkOut;
    final inside = complete && d.isAfter(checkIn!) && d.isBefore(checkOut!);
    return DayLook(
      fill: edge ? accent : null,
      ink: edge ? onAccent : null,
      band: complete && (edge || inside),
      bandStart: d == checkIn,
      bandEnd: d == checkOut,
      strike: isTaken && !edge,
      enabled: enabled,
      label: isTaken ? takenLabel : null,
    );
  }
}
