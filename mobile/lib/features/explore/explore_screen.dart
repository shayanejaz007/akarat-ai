import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/google_map_views.dart' show useGoogleMaps;
import '../../core/widgets/layout.dart';
import '../../core/widgets/listing_image.dart';
import '../../core/widgets/map_layer.dart';
import '../../core/widgets/maps.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/segmented_pill.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/models/listing.dart';
import '../../shared/models/listing_filters.dart';
import '../../shared/reference/market_data.dart';
import '../../shared/widgets/property_card.dart';
import '../property_details/property_details_screen.dart';
import '../tour/tour.dart';
import 'explore_controller.dart';
import 'filters_sheet.dart';

/// Explore opens on a map of every property with a location, sale and rent
/// told apart by colour; the same results are one tap away as a list.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key, this.initialQuery = const {}});

  /// deal, city, hood, type — from Home's shortcuts or a deep link.
  final Map<String, String> initialQuery;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _scroll = ScrollController();
  PageController? _cards;
  double _cardFraction = 0;
  bool _map = true;
  Listing? _selected;

  /// The card swiped to last; the map follows it.
  Listing? _focus;

  /// The listings the cards were built for, to start again at the first
  /// card when the filters change.
  String _cardsFor = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _applyQuery(widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
  }

  @override
  void didUpdateWidget(ExploreScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialQuery.toString() != old.initialQuery.toString()) _applyQuery(widget.initialQuery);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cards?.dispose();
    super.dispose();
  }

  /// One page per card, the next one peeking in; narrower on a tablet.
  PageController _cardController(double width) {
    final fraction = math.min(0.88, 420 / width);
    if (_cards == null || fraction != _cardFraction) {
      _cards?.dispose();
      _cardFraction = fraction;
      _cards = PageController(viewportFraction: fraction);
    }
    return _cards!;
  }

  /// True while the cards scroll to a tapped pin: the cards passed on the
  /// way are not selections.
  bool _cardsFollowingMap = false;

  /// A pin was tapped: its card comes into view.
  Future<void> _selectFromMap(Listing? l, List<Listing> rows) async {
    if (l == null) return;
    setState(() => _selected = l);
    final i = rows.indexWhere((x) => x.id == l.id);
    if (i >= 0 && (_cards?.hasClients ?? false) && (_cards!.page?.round() ?? -1) != i) {
      _cardsFollowingMap = true;
      try {
        await _cards!.animateToPage(i, duration: Motion.of(context, Motion.normal), curve: Motion.standard);
      } finally {
        _cardsFollowingMap = false;
      }
    }
  }

  /// A card was swiped to: its pin is highlighted and the map follows.
  void _selectFromCards(int i, List<Listing> rows) {
    if (_cardsFollowingMap || i < 0 || i >= rows.length) return;
    final l = rows[i];
    if (l.id == _selected?.id) return;
    setState(() {
      _selected = l;
      _focus = l;
    });
  }

  bool _onScreen() => mounted && _map && TickerMode.valuesOf(context).enabled;

  void _maybeTour() {
    if (mounted) unawaited(maybeRunTour(context, ref, TourId.map, visible: _onScreen));
  }

  void _applyQuery(Map<String, String> q) {
    if (q.isEmpty) return;
    final city = Market.city(q['city'])?.id;
    final hood = Market.neighborhood(q['hood']);
    final next = ListingFilters(
      deal: switch (q['deal']) {
        'rent' => DealType.rent,
        'sale' => DealType.sale,
        _ => null,
      },
      cityId: city ?? hood?.city,
      neighborhoodId: hood?.id,
      type: Market.type(q['type'])?.id,
    );
    // After the frame: providers cannot be modified while widgets build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(exploreFiltersProvider.notifier).replace(next);
      if (q['filters'] == '1') unawaited(_openFilters());
    });
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 900) unawaited(ref.read(exploreProvider.notifier).loadMore());
  }

  void _setDeal(DealType? d) {
    final f = ref.read(exploreFiltersProvider);
    ref.read(exploreFiltersProvider.notifier).replace(d == null ? f.copyWith(clearDeal: true) : f.copyWith(deal: d));
  }

  Future<void> _openFilters() async {
    final next = await showFiltersSheet(context, ref.read(exploreFiltersProvider));
    if (next != null) ref.read(exploreFiltersProvider.notifier).replace(next);
  }

  Future<void> _openSort() async {
    final l = context.l10n;
    final current = ref.read(exploreFiltersProvider);
    final picked = await showModalBottomSheet<ListingSort>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
              child: Text(l.exploreSort, style: context.text.titleMedium),
            ),
            for (final (s, label) in [
              (ListingSort.newest, l.sortNewest),
              (ListingSort.priceAsc, l.sortPriceLow),
              (ListingSort.priceDesc, l.sortPriceHigh),
            ])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                title: Text(label),
                selected: s == current.sort,
                trailing: s == current.sort ? Icon(Icons.check_rounded, color: context.colors.emerald) : null,
                onTap: () => Navigator.pop(context, s),
              ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
    if (picked != null) ref.read(exploreFiltersProvider.notifier).replace(current.copyWith(sort: picked));
  }

  void _open(Listing l, {String? hero}) => openProperty(context, l, hero: hero);

  void _toggle() {
    setState(() {
      _map = !_map;
      _selected = null;
    });
    if (_map) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
  }

  @override
  Widget build(BuildContext context) {
    // Profile's "Using the map" guide brings the reader here, on the map.
    ref.listen(pendingTourProvider, (_, next) {
      if (next != TourId.map) return;
      if (!_map) setState(() => _map = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
    });
    final targets = ref.watch(tourTargetsProvider);
    final toggle = _ViewToggle(key: targets.mapToggle, map: _map, onTap: _toggle);
    return _map ? _buildMap(context, toggle) : _buildList(context, toggle);
  }

  Widget _buildMap(BuildContext context, Widget toggle) {
    final l = context.l10n;
    final filters = ref.watch(exploreFiltersProvider);
    final async = ref.watch(exploreMapProvider);
    final all = async.value ?? const <Listing>[];
    final pinned = all.where((x) => x.hasCoordinates).toList();
    // Cards follow the pins first; listings without a location come after.
    final rows = [...pinned, ...all.where((x) => !x.hasCoordinates)];
    final targets = ref.watch(tourTargetsProvider);
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = Layout.inset(context, max: Layout.reading);
    final cards = _cardController(width);
    // New results: back to the first card, nothing selected.
    final signature = rows.map((x) => x.id).join(',');
    if (signature != _cardsFor) {
      _cardsFor = signature;
      _selected = null;
      _focus = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_cards?.hasClients ?? false) _cards!.jumpToPage(0);
      });
    }
    final selected = rows.where((x) => x.id == _selected?.id).firstOrNull;
    final hasSale = pinned.any((x) => !x.isRent);
    final hasRent = pinned.any((x) => x.isRent);
    final cardHeight = 120 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ListingsMap(
              listings: pinned,
              lang: context.lang,
              selected: selected,
              focus: _focus,
              onSelect: (x) => unawaited(_selectFromMap(x, rows)),
              topInset: pad.top + 150,
              bottomInset: (rows.isEmpty ? 72 : cardHeight + 72) + MediaQuery.paddingOf(context).bottom,
            ),
          ),
          // Keeps the status bar legible over any map.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: pad.top + Space.md,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [context.colors.background, context.colors.background.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: pad.top + Space.xs,
            left: inset.left,
            right: inset.right,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Floating(
                        radius: Radii.field,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: SegmentedPill<DealType?>(
                            key: targets.mapDeal,
                            expand: true,
                            height: 40,
                            value: filters.deal,
                            onChanged: _setDeal,
                            segments: [
                              PillSegment(value: null, label: l.mapAll),
                              PillSegment(value: DealType.sale, label: l.dealSale),
                              PillSegment(value: DealType.rent, label: l.dealRent),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Map or satellite (Google's maps only).
                    if (useGoogleMaps(ref)) ...[
                      const SizedBox(width: Space.xs),
                      MapLayerButton(key: targets.mapLayer, compact: true),
                    ],
                    const SizedBox(width: Space.xs),
                    SquareIconButton(
                      key: targets.mapFilters,
                      icon: Icons.tune_rounded,
                      style: SquareStyle.primary,
                      size: 52,
                      badge: filters.activeCount,
                      tooltip: l.exploreFilters,
                      onTap: _openFilters,
                    ),
                  ],
                ),
                if (filters.cityId != null || filters.type != null) ...[
                  const SizedBox(height: Space.xs),
                  _FilterLine(filters: filters, onFilters: _openFilters, padding: EdgeInsets.zero, setOnly: true),
                ],
                const SizedBox(height: Space.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wraps rather than overflows at large text sizes.
                    Flexible(
                      child: _Floating(
                        key: targets.mapLegend,
                        radius: Radii.card,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
                          child: Wrap(
                            spacing: Space.sm,
                            runSpacing: 4,
                            children: [
                              if (hasSale || !hasRent) _LegendDot(colour: MapPins.sale, label: l.badgeForSale),
                              if (hasRent || !hasSale) _LegendDot(colour: MapPins.rent, label: l.badgeForRent),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    _Floating(
                      radius: Radii.chip,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
                        child: async.isLoading && rows.isEmpty
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                              )
                            : Semantics(
                                liveRegion: true,
                                child: Text(l.mapCount(pinned.length), style: context.text.labelMedium),
                              ),
                      ),
                    ),
                  ],
                ),
                if (async.hasError && !async.isLoading) ...[
                  const SizedBox(height: Space.xs),
                  _Floating(
                    child: ErrorState(
                      compact: true,
                      error: async.error!,
                      onRetry: () => ref.invalidate(exploreMapProvider),
                    ),
                  ),
                ] else if (!async.isLoading && pinned.isEmpty) ...[
                  const SizedBox(height: Space.xs),
                  _Floating(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: Text(l.mapNoPins, style: context.text.bodyMedium),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.sm + MediaQuery.paddingOf(context).bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                toggle,
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  SizedBox(
                    height: cardHeight,
                    child: PageView.builder(
                      controller: cards,
                      itemCount: rows.length,
                      onPageChanged: (i) => _selectFromCards(i, rows),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                        child: _MapCard(
                          listing: rows[i],
                          selected: rows[i].id == selected?.id,
                          onOpen: () => _open(rows[i], hero: 'map-${rows[i].id}'),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, Widget toggle) {
    final l = context.l10n;
    final filters = ref.watch(exploreFiltersProvider);
    final async = ref.watch(exploreProvider);
    final header = _ExploreHeader(filters: filters, onDeal: _setDeal, onFilters: _openFilters, onSort: _openSort);

    final inset = Layout.inset(context, max: Layout.grid);
    final slivers = async.when<List<Widget>>(
      skipLoadingOnRefresh: true,
      data: (state) {
        if (state.items.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: l.exploreNoResultsTitle,
                body: l.exploreNoResultsBody,
                action: filters.activeCount > 0
                    ? OutlinedButton(
                        onPressed: () => ref
                            .read(exploreFiltersProvider.notifier)
                            .replace(ListingFilters(deal: filters.deal, sort: filters.sort)),
                        child: Text(l.filterClearAll),
                      )
                    : null,
              ),
            ),
          ];
        }
        return [
          SliverPadding(
            padding: inset.copyWith(top: Space.xs, bottom: Space.md),
            sliver: SliverToBoxAdapter(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l.exploreResultsCount(state.total),
                  style: context.text.labelLarge?.copyWith(color: context.colors.inkMuted),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: inset,
            sliver: SliverCardList(
              itemCount: state.items.length,
              itemBuilder: (context, i) {
                final item = state.items[i];
                return Reveal(
                  index: i,
                  id: 'explore-${item.id}',
                  child: PropertyCard(
                    key: ValueKey(item.id),
                    listing: item,
                    heroTag: 'explore-${item.id}',
                    onTap: () => _open(item, hero: 'explore-${item.id}'),
                  ),
                );
              },
            ),
          ),
          SliverPadding(
            // Clear of the floating Map button.
            padding: inset.copyWith(top: Space.lg, bottom: 80 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverToBoxAdapter(
              child: state.moreError != null
                  ? ErrorState(
                      compact: true,
                      error: state.moreError!,
                      onRetry: ref.read(exploreProvider.notifier).loadMore,
                    )
                  : state.hasMore
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator.adaptive(strokeWidth: 2.4),
                      ),
                    )
                  : Text(l.exploreEnd, textAlign: TextAlign.center, style: context.text.bodySmall),
            ),
          ),
        ];
      },
      loading: () => [
        SliverPadding(
          padding: inset.copyWith(top: Space.md, bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
          sliver: SliverCardList(itemCount: 3, itemBuilder: (_, _) => const PropertyCardSkeleton()),
        ),
      ],
      error: (e, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(error: e, onRetry: () => ref.invalidate(exploreProvider)),
        ),
      ],
    );

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator.adaptive(
            // Sits below the pinned header rather than over the title.
            edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + header.preferredSize.height,
            onRefresh: ref.read(exploreProvider.notifier).refresh,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                LargeTitleBar(title: l.exploreTitle, contentMax: Layout.grid, bottom: header),
                ...slivers,
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.sm + MediaQuery.paddingOf(context).bottom,
            child: Center(child: toggle),
          ),
        ],
      ),
    );
  }
}

/// A floating surface over the map.
class _Floating extends StatelessWidget {
  const _Floating({super.key, required this.child, this.radius = Radii.card});
  final Widget child;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.colour, required this.label});
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
        const SizedBox(width: Space.iconGap),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
        ),
      ],
    );
  }
}

/// Map ↔ list, floating at the bottom in both views.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({super.key, required this.map, required this.onTap});
  final bool map;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Brand forest in both themes, like the other floating action.
    const bg = Color(0xFF123C34);
    return Material(
      color: bg,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(map ? Icons.view_agenda_outlined : Icons.map_outlined, size: 20, color: Colors.white),
              const SizedBox(width: Space.xs),
              Text(map ? l.exploreList : l.exploreMap, style: context.text.labelLarge?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One listing in the row of cards under the map: photo, price, title,
/// place, facts. The card whose pin is highlighted carries a coloured edge.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.listing, required this.selected, required this.onOpen});
  final Listing listing;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final lang = context.lang;
    final place = listing.place(lang);
    final colour = listing.isClosed ? MapPins.closed : (listing.isRent ? MapPins.rent : MapPins.sale);
    return Material(
      color: c.surface,
      elevation: selected ? 6 : 3,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: selected ? BorderSide(color: colour, width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 112,
              margin: const EdgeInsetsDirectional.fromSTEB(6, 6, 0, 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
              child: Hero(
                tag: 'map-${listing.id}',
                child: ListingImage(url: listing.coverUrl, greyscale: listing.isClosed, decodeWidth: 112),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    // Clear of the heart in the corner.
                    padding: const EdgeInsetsDirectional.fromSTEB(Space.sm, Space.xs, 40, Space.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LegendDot(
                          colour: colour,
                          label: listing.isDaily ? l.badgeDaily : (listing.isRent ? l.badgeForRent : l.badgeForSale),
                        ),
                        Text(
                          Fmt.price(listing.priceJod, lang: lang, rent: listing.isRent, night: listing.isDaily),
                          maxLines: 1,
                          style: context.type.priceSmall.copyWith(
                            decoration: listing.isClosed ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        UserText(
                          listing.title(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium,
                        ),
                        if (place.isNotEmpty)
                          Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        if (!listing.hasCoordinates)
                          Row(
                            children: [
                              Icon(Icons.location_off_outlined, size: 13, color: c.inkFaint),
                              const SizedBox(width: Space.xxs),
                              Flexible(
                                child: Text(
                                  l.mapNoLocation,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(color: c.inkFaint),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: FavoriteButton(listingId: listing.id, onImage: false, size: 20),
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

/// All / Buy / Rent, then one scrollable line of what is filtering the list.
/// The line shows only what is set, and every chip opens the filter that set it.
class _ExploreHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ExploreHeader({required this.filters, required this.onDeal, required this.onFilters, required this.onSort});

  final ListingFilters filters;
  final ValueChanged<DealType?> onDeal;
  final VoidCallback onFilters;
  final VoidCallback onSort;

  static const _pill = 40.0;
  static const _chips = 40.0;

  @override
  Size get preferredSize => const Size.fromHeight(_pill + Space.sm + _chips + Space.sm);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // On the card grid's width, so the header lines up with the cards.
    final inset = Layout.inset(context, max: Layout.grid);
    final wide = Layout.isWide(context);
    // The header has a fixed height, so its type is held to a size that
    // fits; the list below it scales freely.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15)),
      child: Column(
        children: [
          Padding(
            padding: inset,
            // Full width on a phone; on a tablet, as wide as its labels.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedPill<DealType?>(
                expand: !wide,
                height: _pill,
                value: filters.deal,
                onChanged: onDeal,
                segments: [
                  PillSegment(value: null, label: l.mapAll),
                  PillSegment(value: DealType.sale, label: l.dealSale),
                  PillSegment(value: DealType.rent, label: l.dealRent),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            width: double.infinity,
            height: _chips,
            child: _FilterLine(
              filters: filters,
              onFilters: onFilters,
              onSort: onSort,
              padding: EdgeInsets.symmetric(horizontal: math.max(inset.left, Space.gutter)),
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

/// Filters, sort (in the list), and a chip for each filter that is set.
class _FilterLine extends StatelessWidget {
  const _FilterLine({
    required this.filters,
    required this.onFilters,
    required this.padding,
    this.onSort,
    this.setOnly = false,
  });

  /// Only the chips for filters that are set (the map has its own button).
  final bool setOnly;

  final ListingFilters filters;
  final VoidCallback onFilters;
  final VoidCallback? onSort;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final sortLabel = switch (filters.sort) {
      ListingSort.newest => l.sortNewest,
      ListingSort.priceAsc => l.sortPriceLow,
      ListingSort.priceDesc => l.sortPriceHigh,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          if (!setOnly)
            _BarChip(
              icon: Icons.tune_rounded,
              label: filters.activeCount > 0 ? '${l.exploreFilters} · ${filters.activeCount}' : l.exploreFilters,
              highlighted: filters.activeCount > 0,
              onTap: onFilters,
            ),
          if (onSort != null) ...[
            const SizedBox(width: Space.xs),
            _BarChip(icon: Icons.swap_vert_rounded, label: sortLabel, onTap: onSort!),
          ],
          if (filters.cityId != null) ...[
            if (!setOnly) const SizedBox(width: Space.xs),
            _BarChip(
              icon: Icons.place_outlined,
              label: Market.placeLabel(filters.cityId, filters.neighborhoodId, lang),
              highlighted: true,
              onTap: onFilters,
            ),
          ],
          if (filters.type != null) ...[
            const SizedBox(width: Space.xs),
            _BarChip(
              icon: Icons.home_work_outlined,
              label: Market.type(filters.type)?.label(lang) ?? filters.type!,
              highlighted: true,
              onTap: onFilters,
            ),
          ],
        ],
      ),
    );
  }
}

/// A rounded, label-sized control in the filter line.
class _BarChip extends StatelessWidget {
  const _BarChip({required this.icon, required this.label, required this.onTap, this.highlighted = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: Material(
        color: highlighted ? Color.alphaBlend(c.emerald.withValues(alpha: 0.12), c.surface) : c.surface,
        shape: StadiumBorder(side: BorderSide(color: highlighted ? c.emerald.withValues(alpha: 0.45) : c.border)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Space.sm, 9, Space.md, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: highlighted ? c.forest : c.inkMuted),
                const SizedBox(width: Space.iconGap),
                Text(
                  label,
                  style: context.text.labelLarge?.copyWith(
                    color: highlighted ? c.forest : c.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
