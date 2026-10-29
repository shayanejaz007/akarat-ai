import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/daily_models.dart';
import '../../shared/models/listing.dart';
import '../../shared/repositories/daily_repository.dart';
import '../../shared/services/supabase_providers.dart';
import 'daily_providers.dart';
import 'month_calendar.dart';
import 'stay_pick.dart';

/// The booking request for a daily rental: dates on a calendar with the
/// taken nights crossed out, the party size, a note, and the total. Resolves
/// true when a request was sent.
Future<bool> showBookingSheet(BuildContext context, Listing listing) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BookingSheet(listing: listing),
  );
  return sent ?? false;
}

class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({super.key, required this.listing});
  final Listing listing;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  late StayPick _pick;
  late DateTime _month;
  late int _guests;
  final _message = TextEditingController();
  String? _error;

  Listing get l => widget.listing;
  int get _maxGuests => (l.maxGuests ?? 16).clamp(1, 50);

  @override
  void initState() {
    super.initState();
    // Dates and guests already chosen on the Daily tab carry over.
    final f = ref.read(dailyFiltersProvider);
    final today = dayOnly(DateTime.now());
    final fromTab = f.dated && !f.checkIn!.isBefore(today);
    _pick = fromTab ? StayPick(checkIn: f.checkIn, checkOut: f.checkOut) : const StayPick();
    _month = fromTab ? f.checkIn! : today;
    _guests = (f.guests ?? 1).clamp(1, _maxGuests);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _tap(DateTime day, Set<DateTime> taken) {
    final next = _pick.tap(day, taken: taken);
    setState(() {
      _pick = next;
      _error = next.crossedTaken ? context.l10n.bookingRangeTaken : null;
    });
  }

  Future<void> _send() async {
    final t = context.l10n;
    if (ref.read(currentUserProvider) == null) {
      Navigator.pop(context, false);
      await context.push(Routes.withNext(Routes.signIn, Routes.property(l.id)));
      return;
    }
    if (!_pick.complete) {
      setState(() => _error = t.bookingPickDates);
      return;
    }
    if (_pick.nights < l.minimumNights) {
      setState(() => _error = t.dailyErrMinNights(l.minimumNights));
      return;
    }
    setState(() => _error = null);
    try {
      await ref
          .read(dailyRepositoryProvider)
          .request(
            propertyId: l.id,
            checkIn: _pick.checkIn!,
            checkOut: _pick.checkOut!,
            guests: _guests,
            message: _message.text,
          );
      ref
        ..invalidate(myBookingsProvider)
        ..invalidate(unavailableDaysProvider(l.id));
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = context.failureMessage(e));
      // Refused for taken nights: the calendar was out of date.
      if (e is DailyRefusal && e.key == 'daily_unavailable') ref.invalidate(unavailableDaysProvider(l.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final today = dayOnly(DateTime.now());
    final taken = ref.watch(unavailableDaysProvider(l.id)).value ?? const <DateTime>{};
    final signedIn = ref.watch(currentUserProvider) != null;
    final nights = _pick.nights;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    Widget dateBox(String label, DateTime? day) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.hair),
            Text(day == null ? t.bookingPickDay : Fmt.night(day, lang: lang), style: context.text.titleSmall),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.bookingTitle, style: context.text.titleLarge),
            const SizedBox(height: Space.xxs),
            Text(t.bookingBody, style: context.text.bodySmall),
            const SizedBox(height: Space.md),
            MonthCalendar(
              month: _month,
              firstMonth: today,
              lastMonth: DateTime(today.year + 1, today.month),
              onMonth: (m) => setState(() => _month = m),
              onTap: (d) => _tap(d, taken),
              look: (d) => _pick.look(
                d,
                today: today,
                accent: c.forest,
                onAccent: c.onForest,
                taken: taken,
                takenLabel: t.availabilityBooked,
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(t.bookingTakenLegend, style: context.text.bodySmall?.copyWith(color: c.inkFaint)),
            const SizedBox(height: Space.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: Radii.field,
                border: Border.all(color: c.border),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    dateBox(t.bookingCheckIn, _pick.checkIn),
                    VerticalDivider(width: 1, color: c.border),
                    dateBox(t.bookingCheckOut, _pick.checkOut),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(child: Text(t.dailyGuests(_guests), style: context.text.titleSmall)),
                IconButton.outlined(
                  tooltip: '−',
                  onPressed: _guests > 1 ? () => setState(() => _guests--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: Space.xs),
                IconButton.outlined(
                  tooltip: '+',
                  onPressed: _guests < _maxGuests ? () => setState(() => _guests++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (l.maxGuests != null)
              Text(t.dailySleeps(l.maxGuests!), style: context.text.bodySmall?.copyWith(color: c.inkFaint)),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: t.bookingMessage,
                hintText: t.bookingMessageHint,
                alignLabelWithHint: true,
              ),
            ),
            if (nights > 0) ...[
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Fmt.price(l.priceJod, lang: lang)} × ${t.dailyNights(nights)}',
                      style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                    ),
                  ),
                  Text(Fmt.price(l.priceJod * nights, lang: lang), style: context.text.bodyMedium),
                ],
              ),
              const Divider(height: Space.lg),
              Row(
                children: [
                  Expanded(child: Text(t.bookingTotal, style: context.text.titleMedium)),
                  Text(
                    Fmt.price(l.priceJod * nights, lang: lang),
                    style: context.text.titleMedium?.copyWith(color: c.forest),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Semantics(
                liveRegion: true,
                child: NoticeLine(icon: Icons.error_outline_rounded, text: _error!, tone: c.danger),
              ),
            ],
            const SizedBox(height: Space.md),
            BusyButton(
              label: signedIn ? t.bookingSend : t.bookingSignIn,
              busyLabel: t.bookingSending,
              icon: signedIn ? Icons.send_rounded : Icons.login_rounded,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}
