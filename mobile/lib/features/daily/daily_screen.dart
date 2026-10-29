import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/listing_image.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/models/daily_models.dart';
import '../../shared/models/listing.dart';
import '../../shared/reference/market_data.dart';
import '../../shared/widgets/pickers.dart';
import 'daily_providers.dart';
import 'month_calendar.dart';
import 'stay_pick.dart';

/// The Daily tab: approved short stays, filtered by dates, party size and
/// city. With dates chosen the database returns only places free for every
/// night, and each card shows the price of the whole stay.
class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});

  Future<void> _pickDates(BuildContext context, WidgetRef ref) async {
    final f = ref.read(dailyFiltersProvider);
    final picked = await showModalBottomSheet<StayPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DatesSheet(
        initial: StayPick(checkIn: f.checkIn, checkOut: f.checkOut),
      ),
    );
    if (picked == null) return;
    final ctrl = ref.read(dailyFiltersProvider.notifier);
    ctrl.set(
      picked.complete ? f.copyWith(checkIn: picked.checkIn, checkOut: picked.checkOut) : f.copyWith(clearDates: true),
    );
  }

  Future<void> _pickGuests(BuildContext context, WidgetRef ref) async {
    final f = ref.read(dailyFiltersProvider);
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (_) => _GuestsSheet(initial: f.guests ?? 2),
    );
    if (picked == null) return;
    ref
        .read(dailyFiltersProvider.notifier)
        .set(picked == 0 ? f.copyWith(clearGuests: true) : f.copyWith(guests: picked));
  }

  Future<void> _pickCity(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final f = ref.read(dailyFiltersProvider);
    final picked = await showChoiceSheet(
      context: context,
      title: l.dailyAllCities,
      options: Market.cities,
      selected: f.cityId,
      anyLabel: l.dailyAllCities,
    );
    if (picked == null) return;
    ref
        .read(dailyFiltersProvider.notifier)
        .set(picked.isEmpty ? f.copyWith(clearCity: true) : f.copyWith(cityId: picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final inset = Layout.inset(context);
    final f = ref.watch(dailyFiltersProvider);
    final async = ref.watch(dailySearchProvider);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final chipHeight = (38 * scaler.scale(1)).clamp(40.0, 60.0);

    final dates = f.dated
        ? '${Fmt.night(f.checkIn!, lang: lang)} → ${Fmt.night(f.checkOut!, lang: lang)}'
        : l.dailyAnyDates;
    final city = Market.city(f.cityId)?.label(lang);

    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + chipHeight + Space.md,
        onRefresh: () async {
          ref.invalidate(dailySearchProvider);
          await ref.read(dailySearchProvider.future).catchError((Object _) => const <Listing>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(
              title: l.dailyTitle,
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(chipHeight + Space.md),
                child: SizedBox(
                  height: chipHeight + Space.md,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: inset.copyWith(top: 0, bottom: Space.md),
                    children: [
                      _FilterChip(
                        icon: Icons.calendar_month_rounded,
                        label: dates,
                        active: f.dated,
                        onTap: () => _pickDates(context, ref),
                      ),
                      const SizedBox(width: Space.xs),
                      _FilterChip(
                        icon: Icons.group_outlined,
                        label: f.guests == null ? l.dailyAnyGuests : l.dailyGuests(f.guests!),
                        active: f.guests != null,
                        onTap: () => _pickGuests(context, ref),
                      ),
                      const SizedBox(width: Space.xs),
                      _FilterChip(
                        icon: Icons.location_city_rounded,
                        label: city ?? l.dailyAllCities,
                        active: city != null,
                        onTap: () => _pickCity(context, ref),
                      ),
                      if (f.any) ...[
                        const SizedBox(width: Space.xs),
                        TextButton(
                          onPressed: () => ref.read(dailyFiltersProvider.notifier).set(const DailyFilters()),
                          child: Text(l.dailyClear),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: inset.copyWith(top: 0, bottom: Space.md),
              sliver: SliverToBoxAdapter(
                child: Text(l.dailySubtitle, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
              ),
            ),
            ...async.when(
              skipLoadingOnReload: true,
              data: (rows) => rows.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.bed_outlined,
                          title: f.any ? l.dailyNoMatchTitle : l.dailyEmptyTitle,
                          body: f.any ? l.dailyNoMatchBody : l.dailyEmptyBody,
                          action: f.any
                              ? OutlinedButton(
                                  onPressed: () => ref.read(dailyFiltersProvider.notifier).set(const DailyFilters()),
                                  child: Text(l.dailyClear),
                                )
                              : FilledButton(
                                  onPressed: () => context.push(Routes.newListing),
                                  child: Text(l.profileListProperty),
                                ),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: inset.copyWith(top: 0, bottom: MediaQuery.paddingOf(context).bottom + Space.xl),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Space.lg),
                          itemBuilder: (context, i) =>
                              DailyCard(key: ValueKey(rows[i].id), listing: rows[i], nights: f.nights),
                        ),
                      ),
                    ],
              loading: () => [
                SliverPadding(
                  padding: inset,
                  sliver: const SliverToBoxAdapter(
                    child: Column(
                      children: [
                        PropertyCardSkeleton(),
                        SizedBox(height: Space.lg),
                        PropertyCardSkeleton(),
                      ],
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(error: e, onRetry: () => ref.invalidate(dailySearchProvider)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      child: Pressable(
        onTap: onTap,
        borderRadius: Radii.chip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Color.alphaBlend(c.emerald.withValues(alpha: 0.12), c.surface) : c.surfaceMuted,
            borderRadius: Radii.chip,
            border: Border.all(color: active ? c.emerald : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: active ? c.forest : c.inkMuted),
              const SizedBox(width: Space.iconGap),
              Text(label, style: context.type.pill.copyWith(color: active ? c.forest : c.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One daily rental in the list: photo with its verified mark and nightly
/// price, then the title, the place, who it sleeps, and the stay's total
/// when dates are chosen.
class DailyCard extends StatelessWidget {
  const DailyCard({super.key, required this.listing, this.nights = 0});
  final Listing listing;
  final int nights;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final x = listing;
    final place = x.place(lang);
    final facts = [
      if (x.maxGuests != null) l.dailySleeps(x.maxGuests!),
      if (x.bedrooms != null && x.bedrooms! > 0) '${x.bedrooms} ${l.specBeds}',
      if (x.minimumNights > 1) l.dailyMinStay(x.minimumNights),
    ];
    return Semantics(
      button: true,
      label: '${x.title(lang)}, ${Fmt.price(x.priceJod, lang: lang, night: true)}, $place',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => context.push(Routes.property(x.id), extra: x),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xl),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListingImage(url: x.coverUrl),
                    PositionedDirectional(
                      top: Space.sm,
                      start: Space.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 4),
                        decoration: BoxDecoration(color: c.surface.withValues(alpha: 0.94), borderRadius: Radii.chip),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 15, color: c.emerald),
                            const SizedBox(width: 4),
                            Text(l.badgeVerified, style: context.type.pill.copyWith(color: c.forest)),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: Space.sm,
                      start: Space.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
                        decoration: BoxDecoration(color: c.ink, borderRadius: Radii.chip),
                        child: Text(
                          Fmt.price(x.priceJod, lang: lang, night: true),
                          style: context.type.pill.copyWith(color: c.background),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            UserText(x.title(lang), maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
            if (place.isNotEmpty) ...[const SizedBox(height: Space.hair), Text(place, style: context.text.bodySmall)],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: Space.xxs),
              Text(facts.join(' · '), style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
            ],
            if (nights > 0) ...[
              const SizedBox(height: Space.xxs),
              Text(
                l.dailyTotalFor(Fmt.price(x.priceJod * nights, lang: lang), l.dailyNights(nights)),
                style: context.text.titleSmall?.copyWith(color: c.forest),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Choosing dates for the Daily tab. Returns the pick; an empty pick clears.
class _DatesSheet extends StatefulWidget {
  const _DatesSheet({required this.initial});
  final StayPick initial;

  @override
  State<_DatesSheet> createState() => _DatesSheetState();
}

class _DatesSheetState extends State<_DatesSheet> {
  late StayPick _pick = widget.initial;
  late DateTime _month = widget.initial.checkIn ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final today = dayOnly(DateTime.now());
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.dailyDates, style: context.text.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            _pick.complete
                ? '${Fmt.night(_pick.checkIn!, lang: lang)} → ${Fmt.night(_pick.checkOut!, lang: lang)} · ${l.dailyNights(_pick.nights)}'
                : (_pick.checkIn == null ? l.bookingCheckIn : l.bookingCheckOut),
            style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: Space.sm),
          MonthCalendar(
            month: _month,
            firstMonth: today,
            lastMonth: DateTime(today.year + 1, today.month),
            onMonth: (m) => setState(() => _month = m),
            onTap: (d) => setState(() => _pick = _pick.tap(d)),
            look: (d) => _pick.look(d, today: today, accent: c.forest, onAccent: c.onForest),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.pop(context, const StayPick()), child: Text(l.dailyClear)),
              const Spacer(),
              FilledButton(
                onPressed: _pick.complete ? () => Navigator.pop(context, _pick) : null,
                child: Text(l.actionApply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How many are coming. Returns the number, or 0 for any.
class _GuestsSheet extends StatefulWidget {
  const _GuestsSheet({required this.initial});
  final int initial;

  @override
  State<_GuestsSheet> createState() => _GuestsSheetState();
}

class _GuestsSheetState extends State<_GuestsSheet> {
  late int _n = widget.initial.clamp(1, 50);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.dailyAnyGuests, style: context.text.titleLarge),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(child: Text(l.dailyGuests(_n), style: context.text.titleMedium)),
              IconButton.outlined(
                tooltip: '−',
                onPressed: _n > 1 ? () => setState(() => _n--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: Space.xs),
              IconButton.outlined(
                tooltip: '+',
                onPressed: _n < 50 ? () => setState(() => _n++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.pop(context, 0), child: Text(l.dailyClear)),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, _n), child: Text(l.actionApply)),
            ],
          ),
        ],
      ),
    );
  }
}
