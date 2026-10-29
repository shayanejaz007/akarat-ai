import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/segmented_pill.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/daily_models.dart';
import 'daily_providers.dart';
import 'request_cards.dart';

/// Daily-rental requests, both ways: those for the owner's places, with
/// approve, decline, confirm and cancel, and the reader's own, with the
/// owner's number and WhatsApp once approved. Live: answers arrive as they
/// are given (dailyLiveProvider).
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key, this.initialTab});

  /// 'requests' (for my places) or 'mine'.
  final String? initialTab;

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  late bool _requests = widget.initialTab != 'mine';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inset = Layout.inset(context);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final pillHeight = 34 * scaler.scale(1) < 40 ? 40.0 : 34 * scaler.scale(1);
    final provider = _requests ? incomingRequestsProvider : myBookingsProvider;
    final async = ref.watch(provider);
    final pending = ref.watch(pendingRequestsProvider);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + pillHeight + Space.md,
        onRefresh: () async {
          ref.invalidate(provider);
          await ref.read(provider.future).catchError((Object _) => const <BookingRequest>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(
              title: l.bookingsTitle,
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(pillHeight + Space.md),
                child: Padding(
                  padding: inset.copyWith(bottom: Space.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SegmentedPill<bool>(
                      expand: !Layout.isWide(context),
                      value: _requests,
                      onChanged: (v) => setState(() => _requests = v),
                      segments: [
                        PillSegment(
                          value: true,
                          label: pending > 0 ? '${l.bookingsRequests} ($pending)' : l.bookingsRequests,
                        ),
                        PillSegment(value: false, label: l.bookingsMine),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ...async.when(
              skipLoadingOnReload: true,
              data: (rows) => rows.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.event_available_outlined,
                          title: _requests ? l.bookingsRequestsEmpty : l.bookingsMineEmpty,
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: inset.copyWith(top: Space.xs, bottom: Space.xxl),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                          itemBuilder: (context, i) => _requests
                              ? OwnerRequestCard(key: ValueKey(rows[i].id), request: rows[i])
                              : RenterRequestCard(key: ValueKey(rows[i].id), request: rows[i]),
                        ),
                      ),
                    ],
              loading: () => [
                SliverPadding(
                  padding: inset.copyWith(top: Space.xs),
                  sliver: const SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Skeleton(height: 140),
                        SizedBox(height: Space.sm),
                        Skeleton(height: 140),
                      ],
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(error: e, onRetry: () => ref.invalidate(provider)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
