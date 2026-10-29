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
import '../../shared/models/listing.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/repositories/media_repository.dart';
import '../../shared/services/refresh.dart';
import '../../shared/widgets/property_card.dart';
import '../daily/daily_providers.dart';
import '../daily/review_notice.dart';
import '../inquiries/inquiries_providers.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final async = ref.watch(myListingsProvider);
    final inquiries = ref.watch(receivedInquiriesProvider);
    final inset = Layout.inset(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newListing),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.profileListProperty),
      ),
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        onRefresh: () async {
          ref
            ..invalidate(myListingsProvider)
            ..invalidate(receivedInquiriesProvider);
          await ref.read(myListingsProvider.future).catchError((Object _) => const <Listing>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(
              title: l.dashboardTitle,
              actions: [
                IconButton(
                  tooltip: l.profileBookings,
                  onPressed: () => context.push(Routes.bookingsFor('requests')),
                  icon: Badge(
                    isLabelVisible: ref.watch(pendingRequestsProvider) > 0,
                    label: Text('${ref.watch(pendingRequestsProvider)}'),
                    child: const Icon(Icons.event_available_outlined),
                  ),
                ),
                IconButton(
                  tooltip: l.profileInquiries,
                  onPressed: () => context.push(Routes.inquiries),
                  icon: const Icon(Icons.mark_email_unread_outlined),
                ),
              ],
            ),
            ...async.when(
              skipLoadingOnReload: true,
              data: (rows) {
                if (rows.isEmpty) {
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.add_home_work_outlined,
                        title: l.dashEmptyTitle,
                        body: l.dashEmptyBody,
                      ),
                    ),
                  ];
                }
                // Live is what the public can see: a daily rental counts only
                // once it is approved.
                bool visible(Listing r) =>
                    r.status == ListingStatus.active && (!r.isDaily || r.dailyReview == DailyReview.approved);
                final live = rows.where(visible).length;
                final hidden = rows.where((r) => !r.isClosed && !visible(r)).length;
                return [
                  SliverPadding(
                    // Room at the end so the last row clears the button.
                    padding: inset.copyWith(top: Space.xs, bottom: 112),
                    sliver: SliverList.list(
                      children: [
                        _Stats(
                          stats: [
                            (l.dashStatListings, rows.length),
                            (l.dashStatLive, live),
                            (l.dashStatHidden, hidden),
                            (l.dashStatInquiries, inquiries.value?.length),
                          ],
                          onInquiries: () => context.push(Routes.inquiries),
                        ),
                        const SizedBox(height: Space.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.insights_outlined, size: 15, color: c.inkFaint),
                            ),
                            const SizedBox(width: Space.iconGap),
                            Expanded(child: Text(l.dashAnalyticsNote, style: context.text.bodySmall)),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        GroupedSection(
                          dividerIndent: Space.md + 96 + Space.sm,
                          children: [for (final row in rows) _ListingRow(key: ValueKey(row.id), listing: row)],
                        ),
                      ],
                    ),
                  ),
                ];
              },
              loading: () => [
                SliverPadding(
                  padding: inset.copyWith(top: Space.xs),
                  sliver: const SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Skeleton(height: 72),
                        SizedBox(height: Space.lg),
                        Skeleton(height: 220),
                      ],
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(error: e, onRetry: () => ref.invalidate(myListingsProvider)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The four numbers on one quiet strip. Inquiries opens the inbox.
class _Stats extends StatelessWidget {
  const _Stats({required this.stats, required this.onInquiries});
  final List<(String, int?)> stats;
  final VoidCallback onInquiries;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, thickness: 1, indent: Space.sm, endIndent: Space.sm, color: c.border),
              Expanded(
                child: InkWell(
                  onTap: i == stats.length - 1 ? onInquiries : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.sm + 2),
                    child: Column(
                      children: [
                        Text(
                          stats[i].$2 == null ? '—' : Fmt.number(stats[i].$2!),
                          style: context.type.figure.copyWith(color: c.forest),
                        ),
                        const SizedBox(height: Space.hair),
                        Text(
                          stats[i].$1,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: context.text.labelSmall?.copyWith(color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingRow extends ConsumerStatefulWidget {
  const _ListingRow({super.key, required this.listing});
  final Listing listing;

  @override
  ConsumerState<_ListingRow> createState() => _ListingRowState();
}

class _ListingRowState extends ConsumerState<_ListingRow> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() action, String done) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final failText = context.failureMessage;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(myListingsProvider);
      ref.read(refreshTickProvider.notifier).bump();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(ListingStatus status) => _act(
    () => ref.read(listingsRepositoryProvider).setStatus(widget.listing.id, status),
    context.l10n.dashStatusUpdated,
  );

  Future<void> _delete() async {
    final l = context.l10n;
    final ok = await confirmAction(
      context,
      title: l.deleteListingTitle,
      body: l.deleteListingBody,
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok) return;
    await _act(() async {
      final paths = widget.listing.media.map((m) => m.path).whereType<String>().toList();
      await ref.read(listingsRepositoryProvider).delete(widget.listing.id);
      // The row is gone, so nothing references these files any more.
      await ref.read(mediaRepositoryProvider).remove(paths);
    }, l.dashDeleted);
  }

  Future<void> _more() async {
    final l = context.l10n;
    final x = widget.listing;
    final live = x.status == ListingStatus.active;
    final picked = await showActionSheet<_RowAction>(
      context,
      title: x.title(context.lang),
      cancelLabel: l.actionCancel,
      actions: [
        if (!x.isClosed)
          SheetAction(
            value: live ? _RowAction.hide : _RowAction.publish,
            label: live ? l.actionHide : l.actionPublish,
            icon: live ? Icons.visibility_off_outlined : Icons.publish_rounded,
          ),
        // A daily rental is never sold or let: it has a calendar instead.
        if (x.isDaily)
          SheetAction(value: _RowAction.availability, label: l.actionAvailability, icon: Icons.calendar_month_outlined)
        else if (!x.isClosed)
          SheetAction(
            value: _RowAction.close,
            label: x.isRent ? l.actionMarkRented : l.actionMarkSold,
            icon: Icons.handshake_outlined,
          ),
        if (x.isClosed) SheetAction(value: _RowAction.relist, label: l.actionRelist, icon: Icons.replay_rounded),
        SheetAction(
          value: _RowAction.delete,
          label: l.actionDelete,
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      // 'paused' is the enum's word for hidden, as on the website.
      case _RowAction.hide:
        await _setStatus(ListingStatus.paused);
      case _RowAction.publish:
      case _RowAction.relist:
        await _setStatus(ListingStatus.active);
      case _RowAction.close:
        await _setStatus(x.isRent ? ListingStatus.rented : ListingStatus.sold);
      case _RowAction.availability:
        await context.push(Routes.availability(x.id));
      case _RowAction.delete:
        await _delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final x = widget.listing;
    final (label, color) = switch (x.status) {
      ListingStatus.active => (l.statusActive, c.emerald),
      ListingStatus.sold => (l.statusSold, c.red),
      ListingStatus.rented => (l.statusRented, c.red),
      ListingStatus.draft => (l.statusDraft, c.inkMuted),
      ListingStatus.pending => (l.statusPending, c.warning),
      ListingStatus.rejected => (l.statusRejected, c.danger),
      ListingStatus.paused => (l.statusPaused, c.inkMuted),
      ListingStatus.archived => (l.statusArchived, c.inkMuted),
    };
    final review = x.isDaily ? reviewTone(context, x) : null;
    // A daily rental not yet approved is not live whatever its status says,
    // so its review is the one badge it shows: room for the whole label.
    final inReview = x.isDaily && x.dailyReview != DailyReview.approved;
    final reviewBadge = review == null
        ? null
        : Tooltip(
            message: x.dailyReviewNote ?? review.label,
            child: ListingBadge(
              label: review.label,
              icon: review.icon,
              background: review.color.withValues(alpha: 0.12),
              foreground: review.color,
            ),
          );
    return PropertyRow(
      listing: x,
      padding: const EdgeInsetsDirectional.fromSTEB(Space.md, Space.sm, Space.xs, Space.xs),
      onTap: () => context.push(Routes.property(x.id), extra: x),
      footer: Row(
        children: [
          // The badges have all the room up to the buttons; a Spacer beside
          // a Flexible would take half of it.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: inReview
                  ? reviewBadge
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListingBadge(label: label, background: color.withValues(alpha: 0.12), foreground: color),
                        if (reviewBadge != null) ...[const SizedBox(width: Space.xxs), Flexible(child: reviewBadge)],
                      ],
                    ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(Space.sm),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            TextButton.icon(
              onPressed: () => context.push(Routes.editListing(x.id)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.actionEdit),
            ),
            IconButton(
              tooltip: l.actionMore,
              onPressed: _more,
              icon: Icon(Icons.more_horiz_rounded, color: c.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

enum _RowAction { hide, publish, close, availability, relist, delete }
