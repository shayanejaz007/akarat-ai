import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/segmented_pill.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/surfaces.dart';
import '../../shared/models/listing.dart';
import '../../shared/reference/market_data.dart';
import '../../shared/services/supabase_providers.dart';
import '../../shared/widgets/pickers.dart';
import '../../shared/widgets/property_card.dart';
import '../property_details/property_details_screen.dart';
import '../tour/tour.dart';
import '../tour/tour_store.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();
  final _header = GlobalKey();

  /// Past the photo: the status bar gets a solid background and dark icons.
  bool _pastHero = false;

  /// Whether Home was in view at the last build: its tab chosen and no page
  /// over it.
  bool _wasInView = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final heroHeight = _header.currentContext?.size?.height ?? 420;
    final past = _scroll.offset > heroHeight * 0.55;
    if (past != _pastHero) setState(() => _pastHero = past);
  }

  bool _inView() => mounted && TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);

  void _maybeTour() {
    if (!mounted || !_inView()) return;
    final due =
        ref.read(pendingTourProvider) == TourId.explore || ref.read(tourStoreProvider).shouldStart(TourId.explore);
    if (!due) return;
    // The tour points at the search and the switches at the top.
    if (_scroll.hasClients && _scroll.offset > 0) {
      unawaited(_scroll.animateTo(0, duration: Motion.of(context, Motion.normal), curve: Motion.standard));
    }
    unawaited(maybeRunTour(context, ref, TourId.explore, visible: _inView));
  }

  static const _featuredCities = [
    'amman',
    'aqaba',
    'irbid',
    'zarqa',
    'salt',
    'madaba',
    'jerash',
    'deadsea',
    'ajloun',
    'karak',
  ];

  /// How many of the newest listings ride in the carousel.
  static const _carousel = 6;

  void _open(BuildContext context, Listing l, String section) =>
      openProperty(context, l, hero: 'home-$section-${l.id}');

  void _explore(BuildContext context, WidgetRef ref, {String? type, String? city}) {
    final deal = ref.read(homeDealProvider);
    final params = <String, String>{'deal': deal.name, 'type': ?type, 'city': ?(city ?? ref.read(homeCityProvider))};
    context.go(Uri(path: Routes.explore, queryParameters: params).toString());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final recent = ref.watch(recentListingsProvider);
    final featured = ref.watch(featuredListingsProvider);
    final featuredRows = featured.value ?? const <Listing>[];
    ref.listen(pendingTourProvider, (_, next) {
      if (next == TourId.explore) _maybeTour();
    });
    // A new account's welcome tour falls due as it is created: try once the
    // sign-up page has closed.
    ref.listen(currentUserProvider, (prev, next) {
      if (next?.userMetadata?['tour_pending'] == true && prev?.userMetadata?['tour_pending'] != true) {
        Future<void>.delayed(const Duration(milliseconds: 900), _maybeTour);
      }
    });
    // Each time Home comes into view (first launch, its tab chosen, a page
    // over it closed), see whether a tour is due.
    final inView = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    if (inView && !_wasInView) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
    _wasInView = inView;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            RefreshIndicator.adaptive(
              onRefresh: () async {
                ref
                  ..invalidate(recentListingsProvider)
                  ..invalidate(featuredListingsProvider);
                await ref.read(recentListingsProvider.future).catchError((Object _) => const <Listing>[]);
              },
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: _HomeHeader(key: _header)),
                  const SliverToBoxAdapter(child: SizedBox(height: Space.md)),
                  SliverToBoxAdapter(
                    child: _TypeGrid(
                      leading: _DealToggle(key: ref.watch(tourTargetsProvider).homeDeal),
                      onTap: (t) => _explore(context, ref, type: t),
                    ),
                  ),
                  if (featuredRows.isNotEmpty) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
                    SliverToBoxAdapter(child: SectionHeader(title: l.homeFeatured)),
                    const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
                    SliverToBoxAdapter(
                      child: _Carousel(
                        section: 'featured',
                        listings: featuredRows,
                        onTap: (x) => _open(context, x, 'featured'),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: Space.lg)),
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: l.homeRecent,
                      action: (recent.value?.isNotEmpty ?? false) ? l.actionSeeAll : null,
                      onAction: () => _explore(context, ref),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
                  SliverToBoxAdapter(
                    child: recent.when(
                      data: (rows) => rows.isEmpty
                          ? EmptyState(
                              compact: true,
                              icon: Icons.storefront_outlined,
                              title: l.homeEmptyTitle,
                              body: l.homeEmptyBody,
                            )
                          : _Carousel(
                              section: 'recent',
                              listings: rows.take(_carousel).toList(),
                              onTap: (x) => _open(context, x, 'recent'),
                            ),
                      loading: () => const _CarouselSkeleton(),
                      error: (e, _) =>
                          ErrorState(compact: true, error: e, onRetry: () => ref.invalidate(recentListingsProvider)),
                    ),
                  ),
                  if ((recent.value?.length ?? 0) > _carousel) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
                    SliverToBoxAdapter(
                      child: SectionHeader(
                        title: l.homeMore,
                        action: l.actionSeeAll,
                        onAction: () => _explore(context, ref),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
                    _CompactGrid(
                      listings: recent.value!.skip(_carousel).toList(),
                      onTap: (x) => _open(context, x, 'more'),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
                  SliverToBoxAdapter(child: SectionHeader(title: l.homeCities)),
                  const SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
                  SliverToBoxAdapter(
                    child: _CityStrip(
                      cities: _featuredCities,
                      onTap: (c) => _explore(context, ref, city: c),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
                  const SliverToBoxAdapter(child: _ListCta()),
                  // Clear of the floating tab bar.
                  SliverToBoxAdapter(child: SizedBox(height: Space.xl + MediaQuery.paddingOf(context).bottom)),
                ],
              ),
            ),
            // Once the photo has scrolled away, content no longer runs under a
            // bare status bar.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _pastHero ? 1 : 0,
                  duration: Motion.of(context, Motion.fast),
                  child: ColoredBox(color: c.background),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({super.key});

  Future<void> _pickCity(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final picked = await showChoiceSheet(
      context: context,
      title: l.locationPickerTitle,
      options: Market.cities,
      selected: ref.read(homeCityProvider),
      anyLabel: l.locationAllJordan,
    );
    if (picked == null) return;
    await ref.read(homeCityProvider.notifier).set(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final deal = ref.watch(homeDealProvider);
    final cityId = ref.watch(homeCityProvider);
    final cityName = Market.city(cityId)?.label(context.lang) ?? l.locationAllJordan;
    final targets = ref.watch(tourTargetsProvider);
    final user = ref.watch(currentUserProvider);
    final name = (user?.userMetadata?['full_name'] as String?)?.trim() ?? '';
    final initial = name.isNotEmpty
        ? name.characters.first.toUpperCase()
        : (user?.email ?? '').characters.firstOrNull?.toUpperCase();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Where to look: the city everything below is filtered by.
                Expanded(
                  child: Semantics(
                    key: targets.homeCity,
                    button: true,
                    label: '${l.locationPickerTitle}: $cityName',
                    excludeSemantics: true,
                    child: Pressable(
                      onTap: () => _pickCity(context, ref),
                      borderRadius: Radii.tile,
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.tile),
                            child: Icon(Icons.location_on_rounded, color: c.ink, size: 22),
                          ),
                          const SizedBox(width: Space.sm),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(l.homeLocation, style: context.text.labelSmall?.copyWith(color: c.inkMuted)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        cityName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.titleSmall,
                                      ),
                                    ),
                                    Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: c.ink),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                // The account: initials once signed in.
                if (user != null && initial != null)
                  Semantics(
                    button: true,
                    label: l.tabProfile,
                    excludeSemantics: true,
                    child: Pressable(
                      onTap: () => context.go(Routes.profile),
                      borderRadius: Radii.tile,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.tile),
                        child: Text(initial, style: context.text.titleMedium),
                      ),
                    ),
                  )
                else
                  SquareIconButton(
                    icon: Icons.person_outline_rounded,
                    tooltip: l.tabProfile,
                    onTap: () => context.go(Routes.profile),
                  ),
              ],
            ),
            SizedBox(height: MediaQuery.sizeOf(context).height < 500 ? Space.md : Space.xl),
            Row(
              children: [
                Expanded(child: _SearchEntry(key: targets.homeSearch)),
                const SizedBox(width: Space.sm),
                SquareIconButton(
                  icon: Icons.tune_rounded,
                  style: SquareStyle.primary,
                  size: 52,
                  tooltip: l.exploreFilters,
                  onTap: () => context.go(
                    Uri(path: Routes.explore, queryParameters: {'deal': deal.name, 'filters': '1'}).toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Looks like a field; opens AI Search with its keyboard up, where the real
/// input lives — one place to type a request and one parser reading it. The
/// microphone inside opens it listening.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Material(
      color: c.surfaceMuted,
      borderRadius: Radii.field,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: l.homeAiCta,
                hint: l.homeSearchPrompt,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: Radii.field,
                  onTap: () => context.go('${Routes.aiSearch}?focus=${DateTime.now().millisecondsSinceEpoch}'),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: Space.md),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: c.ink, size: 22),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            l.homeSearchPrompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l.a11yVoice,
              onPressed: () => context.go('${Routes.aiSearch}?voice=${DateTime.now().millisecondsSinceEpoch}'),
              icon: Icon(Icons.mic_none_rounded, color: c.emerald),
            ),
            const SizedBox(width: Space.xxs),
          ],
        ),
      ),
    );
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.section, required this.listings, required this.onTap});
  final String section;
  final List<Listing> listings;
  final ValueChanged<Listing> onTap;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(260.0, 380.0);
    return SizedBox(
      height: PropertyCard.heightFor(context, width),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: listings.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: (context, i) => Reveal(
          index: i,
          id: 'home-$section-${listings[i].id}',
          child: PropertyCard(
            listing: listings[i],
            width: width,
            heroTag: 'home-$section-${listings[i].id}',
            onTap: () => onTap(listings[i]),
          ),
        ),
      ),
    );
  }
}

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(260.0, 380.0);
    return SizedBox(
      height: PropertyCard.heightFor(context, width),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: (_, _) => PropertyCardSkeleton(width: width),
      ),
    );
  }
}

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.onTap, required this.leading});
  final ValueChanged<String> onTap;

  /// First in the row: Buy / Rent.
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    return SizedBox(
      height: 56 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: Market.types.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: Space.xs),
        itemBuilder: (context, i) {
          if (i == 0) return leading;
          final t = Market.types[i - 1];
          // A grey chip with its icon in a white well; sized to its label.
          return Pressable(
            onTap: () => onTap(t.id),
            borderRadius: Radii.field,
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 6, Space.md, 6),
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.field),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
                    child: Icon(propertyTypeIcon(t.id), color: c.ink, size: 20),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(t.label(lang), style: context.text.labelLarge),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Buy or rent, as the first grey pill in the row of kinds; everything on
/// Home follows it.
class _DealToggle extends ConsumerWidget {
  const _DealToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Center(
      child: SegmentedPill<DealType>(
        height: 52,
        value: ref.watch(homeDealProvider),
        onChanged: (d) => ref.read(homeDealProvider.notifier).set(d),
        segments: [
          PillSegment(value: DealType.sale, label: l.dealSale),
          PillSegment(value: DealType.rent, label: l.dealRent),
        ],
      ),
    );
  }
}

/// The reference's second row: smaller cards, two to a line.
class _CompactGrid extends StatelessWidget {
  const _CompactGrid({required this.listings, required this.onTap});
  final List<Listing> listings;
  final ValueChanged<Listing> onTap;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 700 ? 3 : 2;
    final rows = (listings.length / columns).ceil();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverList.separated(
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, r) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var k = 0; k < columns; k++) ...[
              if (k > 0) const SizedBox(width: Space.sm),
              Expanded(
                child: r * columns + k < listings.length
                    ? Reveal(
                        index: k,
                        id: 'home-more-${listings[r * columns + k].id}',
                        child: PropertyCardCompact(
                          listing: listings[r * columns + k],
                          heroTag: 'home-more-${listings[r * columns + k].id}',
                          onTap: () => onTap(listings[r * columns + k]),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CityStrip extends StatelessWidget {
  const _CityStrip({required this.cities, required this.onTap});
  final List<String> cities;
  final ValueChanged<String> onTap;

  // The brand's forest in every theme: these tiles carry white type, and the
  // dark theme's forest token is a light mint meant for text, not fills.
  static const _deep = Color(0xFF123C34);
  static const _deeper = Color(0xFF0B231F);
  static const _gold = Color(0xFFD9B25E);

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    return SizedBox(
      height: 120 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: cities.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final city = Market.city(cities[i])!;
          return Pressable(
            onTap: () => onTap(city.id),
            borderRadius: Radii.card,
            child: Container(
              width: 148,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                borderRadius: Radii.card,
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [_deep, _deeper],
                ),
              ),
              child: Stack(
                children: [
                  // The Arabic name as a quiet watermark, in both languages.
                  PositionedDirectional(
                    top: -12,
                    end: -4,
                    child: ExcludeSemantics(
                      child: Text(
                        city.ar,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'IBMPlexSansArabic',
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(width: 18, height: 2, color: _gold),
                        const SizedBox(height: Space.xs),
                        Text(
                          city.label(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(color: Colors.white),
                        ),
                        Text(
                          lang == 'ar' ? city.en : city.ar,
                          maxLines: 1,
                          style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ListCta extends StatelessWidget {
  const _ListCta();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.xl)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BrandMark(size: 36),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(l.homeListCtaTitle, style: context.text.titleLarge)),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(l.homeListCtaBody, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.md),
            FilledButton.icon(
              onPressed: () => unawaited(context.push(Routes.newListing)),
              icon: const Icon(Icons.add_home_outlined),
              label: Text(l.homeListCtaButton),
            ),
          ],
        ),
      ),
    );
  }
}
