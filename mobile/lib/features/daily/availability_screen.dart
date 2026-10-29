import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/models/daily_models.dart';
import '../../shared/repositories/daily_repository.dart';
import '../../shared/repositories/listings_repository.dart';
import 'daily_providers.dart';
import 'month_calendar.dart';

final _blockedDaysProvider = FutureProvider.autoDispose.family<Set<DateTime>, String>(
  (ref, id) => ref.watch(dailyRepositoryProvider).blockedDays(id),
);

/// An owner's calendar for one daily rental. Tapping a day closes it to
/// requests, or opens it again; nights inside a confirmed stay are closed by
/// the stay itself and cannot be opened here.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key, required this.listingId});
  final String listingId;

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  DateTime _month = DateTime.now();

  /// Days changed here and not yet confirmed by the database, so a tap shows
  /// at once and is put back if the write fails.
  final _closed = <DateTime>{};
  final _opened = <DateTime>{};

  Future<void> _toggle(DateTime day, bool closedNow) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = context.failureMessage;
    setState(() {
      if (closedNow) {
        _closed.remove(day);
        _opened.add(day);
      } else {
        _opened.remove(day);
        _closed.add(day);
      }
    });
    try {
      await ref.read(dailyRepositoryProvider).setBlocked(widget.listingId, day, blocked: !closedNow);
      ref.invalidate(unavailableDaysProvider(widget.listingId));
    } on Object catch (e) {
      setState(() {
        _closed.remove(day);
        _opened.remove(day);
      });
      messenger.showSnackBar(SnackBar(content: Text(message(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final inset = Layout.inset(context);
    final today = dayOnly(DateTime.now());
    final listing = ref.watch(listingByIdProvider(widget.listingId)).value;
    final blocked = ref.watch(_blockedDaysProvider(widget.listingId));
    final requests = ref.watch(incomingRequestsProvider).value ?? const <BookingRequest>[];
    final booked = <DateTime>{
      for (final r in requests)
        if (r.status == BookingStatus.confirmed && r.propertyId == widget.listingId)
          for (var d = r.checkIn; d.isBefore(r.checkOut); d = DateTime(d.year, d.month, d.day + 1)) d,
    };

    Widget legend(Color? fill, Color? border, String label, {bool strike = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: border == null ? null : Border.all(color: border),
          ),
        ),
        const SizedBox(width: Space.iconGap),
        Text(label, style: context.text.bodySmall),
      ],
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          LargeTitleBar(title: l.availabilityTitle),
          SliverPadding(
            padding: inset.copyWith(top: Space.xs, bottom: Space.xxl),
            sliver: SliverToBoxAdapter(
              child: blocked.when(
                data: (stored) {
                  bool isClosed(DateTime d) => (stored.contains(d) || _closed.contains(d)) && !_opened.contains(d);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (listing != null) ...[
                        UserText(listing.title(lang), style: context.text.titleMedium),
                        const SizedBox(height: Space.xxs),
                      ],
                      Text(l.availabilityBody, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
                      const SizedBox(height: Space.md),
                      MonthCalendar(
                        month: _month,
                        firstMonth: today,
                        lastMonth: DateTime(today.year + 1, today.month),
                        onMonth: (m) => setState(() => _month = m),
                        onTap: (d) => _toggle(d, isClosed(d)),
                        look: (d) {
                          final past = d.isBefore(today);
                          if (booked.contains(d)) {
                            return DayLook(
                              fill: c.forest,
                              ink: c.onForest,
                              enabled: false,
                              label: l.availabilityBooked,
                            );
                          }
                          final closed = isClosed(d);
                          return DayLook(
                            fill: closed ? c.danger.withValues(alpha: 0.14) : null,
                            ink: closed ? c.danger : null,
                            strike: closed,
                            enabled: !past,
                            label: closed ? l.availabilityClosed : l.availabilityOpen,
                          );
                        },
                      ),
                      const SizedBox(height: Space.md),
                      Wrap(
                        spacing: Space.md,
                        runSpacing: Space.xs,
                        children: [
                          legend(null, c.border, l.availabilityOpen),
                          legend(c.danger.withValues(alpha: 0.3), null, l.availabilityClosed),
                          legend(c.forest, null, l.availabilityBooked),
                        ],
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) =>
                    ErrorState(error: e, onRetry: () => ref.invalidate(_blockedDaysProvider(widget.listingId))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One listing by id, for screens that only have the id.
final listingByIdProvider = FutureProvider.autoDispose.family(
  (ref, String id) => ref.watch(listingsRepositoryProvider).byId(id),
);
