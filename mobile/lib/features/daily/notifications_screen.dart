import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/daily_models.dart';
import '../../shared/repositories/daily_repository.dart';
import 'daily_providers.dart';

/// What happened to this person's requests and daily listings, newest
/// first. Opening the list marks everything read.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rows = await ref.read(notificationsProvider.future).catchError((Object _) => const <AppNotification>[]);
      if (!mounted || rows.every((n) => !n.unread)) return;
      await ref.read(dailyRepositoryProvider).markAllRead();
      // Shown once more as they were, unread dots and all; the badge clears.
      if (mounted) ref.invalidate(notificationsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inset = Layout.inset(context);
    final async = ref.watch(notificationsProvider);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future).catchError((Object _) => const <AppNotification>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(title: l.notificationsTitle),
            ...async.when(
              skipLoadingOnReload: true,
              data: (rows) => rows.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(icon: Icons.notifications_none_rounded, title: l.notificationsEmpty),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: inset.copyWith(top: Space.xs, bottom: Space.xxl),
                        sliver: SliverToBoxAdapter(
                          child: GroupedSection(
                            dividerIndent: Space.md + 10 + Space.sm,
                            children: [for (final n in rows) _NotificationRow(key: ValueKey(n.id), n: n)],
                          ),
                        ),
                      ),
                    ],
              loading: () => [
                SliverPadding(
                  padding: inset.copyWith(top: Space.xs),
                  sliver: const SliverToBoxAdapter(child: Skeleton(height: 220)),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The sentence for a notification, in the reader's language.
String notificationText(BuildContext context, AppNotification n) {
  final l = context.l10n;
  final title = n.title(context.lang);
  final name = n.text('renter_name').isEmpty ? l.notifGuest : n.text('renter_name');
  final note = n.text('note');
  final reason = note.isEmpty ? '' : ' ${l.notifReason(note)}';
  return switch (n.kind) {
    'booking_new' => l.notifBookingNew(name, title),
    'booking_approved' => l.notifBookingApproved(title),
    'booking_rejected' =>
      n.text('reason') == 'dates_taken' ? l.notifBookingDatesTaken(title) : l.notifBookingRejected(title) + reason,
    'booking_confirmed' => l.notifBookingConfirmed(title),
    'booking_cancelled' =>
      n.text('by') == 'renter'
          ? l.notifBookingCancelledByRenter(name, title)
          : l.notifBookingCancelledByOwner(title) + reason,
    'listing_approved' => l.notifListingApproved(title),
    'listing_rejected' => l.notifListingRejected(title) + reason,
    'listing_suspended' => l.notifListingSuspended(title) + reason,
    'listing_unapproved' => l.notifListingUnapproved(title) + reason,
    _ => title,
  };
}

/// Where a notification leads: the requests it is about, or the listing.
String notificationTarget(AppNotification n) {
  final forOwner = n.kind == 'booking_new' || (n.kind == 'booking_cancelled' && n.text('by') == 'renter');
  if (forOwner) return Routes.bookingsFor('requests');
  if (n.kind.startsWith('booking_')) return Routes.bookingsFor('mine');
  return n.propertyId != null ? Routes.property(n.propertyId!) : Routes.dashboard;
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({super.key, required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    final dates = n.checkIn != null && n.checkOut != null
        ? '${Fmt.night(n.checkIn!, lang: lang)} → ${Fmt.night(n.checkOut!, lang: lang)}'
        : null;
    return InkWell(
      onTap: () => unawaited(context.push(notificationTarget(n))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: n.unread ? c.red : Colors.transparent, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notificationText(context, n), style: context.text.bodyMedium),
                  if (dates != null) Text(dates, style: context.text.bodySmall),
                  const SizedBox(height: Space.hair),
                  Text(
                    Fmt.date(n.createdAt, lang: lang),
                    style: context.text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
