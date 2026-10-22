import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/config/env.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/listing_image.dart';
import '../../core/widgets/maps.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/models/listing.dart';
import '../../shared/models/search_constraints.dart';
import '../../shared/reference/market_data.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/services/refresh.dart';
import '../../shared/services/supabase_providers.dart';
import '../../shared/widgets/pickers.dart';
import '../../shared/widgets/property_card.dart';
import '../ai_search/presentation/ai_search_controller.dart';
import '../inquiries/inquiry_sheet.dart';
import '../moderation/listing_actions.dart';
import '../tour/tour.dart';
import 'media_viewer.dart';

final listingDetailProvider = FutureProvider.autoDispose.family<Listing?, String>((ref, id) {
  ref.watch(refreshTickProvider);
  return ref.watch(listingsRepositoryProvider).byId(id);
});

/// Keyed by the facts that decide similarity, not by the row object, so a
/// refreshed copy of the same listing does not refetch its neighbours.
typedef SimilarKey = ({String id, DealType deal, String? city, String type});

final similarListingsProvider = FutureProvider.autoDispose.family<List<Listing>, SimilarKey>((ref, k) {
  return ref.watch(listingsRepositoryProvider).similar(id: k.id, deal: k.deal, cityId: k.city, type: k.type);
});

/// What a screen hands the detail page when it opens a listing: the row it
/// already has, and the tag of the photo that should fly into the gallery.
class PropertyRouteArgs {
  const PropertyRouteArgs(this.listing, {this.heroTag});
  final Listing listing;
  final String? heroTag;
}

/// Opens a listing. [hero] is the tag on the card's photo, unique to where
/// the card is (`explore-…`, `home-recent-…`), so the photo can travel.
void openProperty(BuildContext context, Listing l, {String? hero}) {
  unawaited(context.push(Routes.property(l.id), extra: hero == null ? l : PropertyRouteArgs(l, heroTag: hero)));
}

class PropertyDetailsScreen extends ConsumerWidget {
  const PropertyDetailsScreen({super.key, required this.id, this.initial, this.heroTag});
  final String id;

  /// The card photo that flies in as the first gallery image.
  final String? heroTag;

  /// The row the previous screen already had, shown at once while the
  /// current version is fetched — so the page is never blank, and never
  /// stale for long.
  final Listing? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listingDetailProvider(id));
    final listing = async.value ?? (async.hasError || (async.hasValue && async.value == null) ? null : initial);

    if (listing == null) {
      if (async.isLoading) return const _DetailSkeleton();
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.hasError
              ? ErrorState(error: async.error!, onRetry: () => ref.invalidate(listingDetailProvider(id)))
              : EmptyState(icon: Icons.home_work_outlined, title: context.l10n.detailsNotFound),
        ),
      );
    }
    return _Details(listing: listing, heroTag: heroTag);
  }
}

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.listing, this.heroTag});
  final String? heroTag;
  final Listing listing;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  final _scroll = ScrollController();
  int _page = 0;
  bool _descOpen = false;

  /// Once the photo has scrolled away the bar turns plain: dark icons, no
  /// discs, and the listing's title.
  bool _collapsed = false;

  Listing get l => widget.listing;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // A listing's own tour, the first time one opens (or from Guides).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(maybeRunTour(context, ref, TourId.property, visible: _inView));
    });
  }

  bool _inView() => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static double _galleryHeight(Size size) => math.min(math.max(size.height * 0.44, 220), 540);

  /// The photo's margin from the screen edges.
  static const double _photoInset = Space.xs;

  final _specsKey = GlobalKey();
  final _locationKey = GlobalKey();

  void _onScroll() {
    final threshold =
        _galleryHeight(MediaQuery.sizeOf(context)) +
        _photoInset -
        kToolbarHeight -
        MediaQuery.paddingOf(context).top -
        Space.lg;
    final collapsed = _scroll.offset > threshold;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  /// Scrolls a section into view, just under the bar ("See all", the map pill).
  void _reveal(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: Motion.of(context, Motion.slow),
        curve: Motion.emphasized,
        alignment: 0.12,
      ),
    );
  }

  Future<void> _share() async {
    final lang = context.lang;
    final url = Env.listingWebUrl(l.id, lang);
    await SharePlus.instance.share(ShareParams(text: '${l.title(lang)}\n$url', subject: l.title(lang), uri: null));
  }

  Future<void> _call(String phone) async {
    final target = Phone.dialable(phone);
    if (target == null) return;
    await launchUrl(Uri(scheme: 'tel', path: target));
  }

  Future<void> _whatsapp(String phone) async {
    final target = Phone.whatsappTarget(phone);
    if (target == null) return;
    await launchUrl(
      Uri.https('wa.me', '/$target', {'text': l.title(context.lang)}),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _enquire() async {
    final text = context.l10n.inquirySent;
    final sent = await showInquirySheet(context, l);
    if (sent && mounted) showSuccess(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final media = l.media;
    final mine = ref.watch(currentUserProvider)?.id == l.ownerId;
    final phone = l.payload.contact.phone;
    final canContact = !l.isClosed && !mine;
    final onCall = phone.isEmpty ? null : () => _call(phone);
    final onEnquire = l.status == ListingStatus.active ? _enquire : null;
    final description = l.description(lang);
    final type = Market.type(l.propertyType)?.label(lang) ?? l.propertyType;
    final inset = Layout.inset(context);
    final hasBar = canContact && (onCall != null || onEnquire != null);
    final targets = ref.watch(tourTargetsProvider);

    void openViewer(int i) => MediaViewer.open(
      context,
      media,
      i,
      title: l.title(lang),
      tags: [for (var k = 0; k < media.length; k++) _Gallery.tagFor(l, k, widget.heroTag)],
    );

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: _galleryHeight(MediaQuery.sizeOf(context)) + _photoInset,
            backgroundColor: c.background,
            foregroundColor: c.ink,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            // Light status-bar icons over the photo, the theme's once plain.
            systemOverlayStyle: _collapsed ? null : SystemUiOverlayStyle.light,
            shape: _collapsed ? Border(bottom: BorderSide(color: c.border)) : null,
            titleSpacing: Space.xs,
            // Square buttons sit inside the photo's rounded corners.
            leadingWidth: _photoInset + Space.xs + _BarAction.size,
            title: AnimatedOpacity(
              opacity: _collapsed ? 1 : 0,
              duration: Motion.of(context, Motion.fast),
              child: UserText(
                l.title(lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
            ),
            leading: Padding(
              padding: const EdgeInsetsDirectional.only(start: _photoInset + Space.xs),
              child: Center(
                child: _BarAction(
                  icon: Icons.arrow_back_rounded,
                  overImage: !_collapsed,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
                ),
              ),
            ),
            actions: [
              // Report the listing or hide its advertiser; not on your own.
              if (!mine) ...[
                _BarAction(
                  icon: Icons.more_horiz_rounded,
                  overImage: !_collapsed,
                  tooltip: t.detailsMore,
                  onTap: () => showListingActions(context, ref, l),
                ),
                const SizedBox(width: Space.xs),
              ],
              _BarAction(icon: Icons.ios_share_rounded, overImage: !_collapsed, tooltip: t.actionShare, onTap: _share),
              const SizedBox(width: Space.xs),
              KeyedSubtree(
                key: targets.propertySave,
                child: FavoriteButton(listingId: l.id, onImage: !_collapsed, squared: true),
              ),
              const SizedBox(width: _photoInset + Space.xs),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              // The photo as an inset card with rounded corners, as in the
              // reference, rather than edge to edge.
              background: Padding(
                padding: const EdgeInsets.fromLTRB(_photoInset, _photoInset, _photoInset, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.xl + 4),
                  child: _Gallery(
                    listing: l,
                    heroTag: widget.heroTag,
                    onPage: (i) => setState(() => _page = i),
                    page: _page,
                    onOpen: openViewer,
                    onMap: l.hasCoordinates ? () => _reveal(_locationKey) : null,
                    pillsKey: targets.propertyPhotos,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: inset.copyWith(top: Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kind of place on the start side, the deal (or its end) on
                  // the other, as soft grey pills.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: Space.xs,
                          runSpacing: Space.xs,
                          children: [
                            _SoftBadge(icon: propertyTypeIcon(l.propertyType), label: type),
                            if (l.verified)
                              _SoftBadge(icon: Icons.verified_rounded, label: t.badgeVerified, tint: c.emerald),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      if (l.isClosed)
                        _SoftBadge(dot: c.red, label: l.status == ListingStatus.rented ? t.badgeRented : t.badgeSold)
                      else
                        _SoftBadge(
                          dot: l.isRent ? const Color(0xFFD9B25E) : c.emerald,
                          label: l.isRent ? t.badgeForRent : t.badgeForSale,
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Semantics(header: true, child: UserText(l.title(lang), style: context.text.headlineLarge)),
                  if (l.place(lang).isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 19, color: c.ink),
                        const SizedBox(width: Space.iconGap),
                        Expanded(
                          child: Text(l.place(lang), style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
                        ),
                      ],
                    ),
                  ],
                  if (!hasBar) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      Fmt.price(l.priceJod, lang: lang, rent: l.isRent),
                      style: context.type.priceLarge.copyWith(
                        color: l.isClosed ? c.inkMuted : c.ink,
                        decoration: l.isClosed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                  if (l.isClosed) ...[
                    const SizedBox(height: Space.md),
                    NoticeLine(
                      icon: Icons.info_outline_rounded,
                      tone: c.red,
                      text: l.status == ListingStatus.rented ? t.detailsClosedRented : t.detailsClosedSold,
                    ),
                  ],
                  if (mine) ...[const SizedBox(height: Space.md), _OwnerBanner(listing: l)],
                  if (_Facilities.hasAny(l)) ...[
                    _divider(),
                    _Title(t.detailsFacilities, action: t.actionSeeAll, onAction: () => _reveal(_specsKey)),
                    _Facilities(listing: l),
                  ],
                  if (description.isNotEmpty) ...[
                    _divider(),
                    _Title(t.detailsAbout),
                    _ReadMore(
                      text: description,
                      open: _descOpen,
                      onToggle: () => setState(() => _descOpen = !_descOpen),
                    ),
                  ],
                  if (canContact) ...[
                    // The owner, with chat and call at hand, right under what
                    // the reader came for; the inquiry is the bar's action.
                    const SizedBox(height: Space.lg),
                    _ContactCard(
                      listing: l,
                      onWhatsApp: phone.isEmpty || !l.payload.contact.whatsapp ? null : () => _whatsapp(phone),
                      onCall: onCall,
                      enquiriesOpen: onEnquire != null,
                    ),
                  ],
                  _divider(),
                  _Title(t.detailsSpecs, key: _specsKey),
                  _Specs(listing: l),
                  if (l.payload.amenities.isNotEmpty) ...[
                    _divider(),
                    _Title(t.detailsAmenities),
                    _Amenities(ids: l.payload.amenities),
                  ],
                  _divider(),
                  _Title(t.detailsLocation, key: _locationKey),
                  _Location(listing: l),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.specRef} ${l.id.substring(0, 8)}',
                          style: context.text.labelSmall?.copyWith(color: c.inkFaint),
                        ),
                      ),
                      // Also in the bar's "More", but here too, where the
                      // reader finishes reading.
                      if (!mine)
                        TextButton.icon(
                          onPressed: () => reportListing(context, ref, l),
                          icon: const Icon(Icons.flag_outlined, size: 18),
                          label: Text(t.reportListing),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _Similar(listing: l)),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xxl)),
        ],
      ),
      bottomNavigationBar: hasBar
          ? _StickyBar(listing: l, onCall: onCall, onEnquire: onEnquire, actionKey: targets.propertyContact)
          : null,
    );
  }

  Widget _divider() => const SizedBox(height: Space.xl);
}

/// A section's title, with an optional quiet "See all" on the end.
class _Title extends StatelessWidget {
  const _Title(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(text, style: context.text.headlineSmall)),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: c.inkMuted,
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
            ),
        ],
      ),
    );
  }
}

/// A bar button: a white rounded square over the photo, a plain icon once
/// the bar is solid.
class _BarAction extends StatelessWidget {
  const _BarAction({required this.icon, required this.onTap, required this.tooltip, required this.overImage});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool overImage;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: overImage ? Colors.white.withValues(alpha: 0.92) : Colors.transparent,
        borderRadius: Radii.tile,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        // Arrow glyphs mirror themselves in Arabic.
        icon: Icon(icon, color: overImage ? const Color(0xFF16201D) : c.ink, size: 22),
      ),
    );
  }
}

/// A soft grey badge under the photo: type, deal, verified.
class _SoftBadge extends StatelessWidget {
  const _SoftBadge({required this.label, this.icon, this.dot, this.tint});
  final String label;
  final IconData? icon;
  final Color? dot;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.tile),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null)
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            )
          else if (icon != null)
            Icon(icon, size: 17, color: tint ?? c.ink),
          const SizedBox(width: Space.iconGap),
          Text(label, style: context.text.labelLarge),
        ],
      ),
    );
  }
}

/// The counts that matter most, as three tiles across, as in the reference:
/// bedrooms, bathrooms and size (parking or land when one is missing). The
/// rest are under Property details and Features, which "See all" scrolls to.
class _Facilities extends StatelessWidget {
  const _Facilities({required this.listing});
  final Listing listing;

  static bool hasAny(Listing l) =>
      (l.bedrooms ?? 0) > 0 || (l.bathrooms ?? 0) > 0 || l.areaSqm != null || l.landSqm != null;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final lang = context.lang;
    final all = <(IconData, String)>[
      if (listing.bedrooms case final b? when b > 0) (Icons.bed_rounded, t.a11yBeds(b)),
      if (listing.bathrooms case final b? when b > 0) (Icons.bathtub_rounded, t.a11yBaths(b)),
      if (listing.areaSqm case final a?) (Icons.square_foot_rounded, Fmt.area(a, lang: lang)),
      if (listing.areaSqm == null && listing.landSqm != null)
        (Icons.landscape_rounded, Fmt.area(listing.landSqm!, lang: lang)),
      if (listing.payload.amenities.contains('parking'))
        (Icons.garage_rounded, Market.amenity('parking')?.label(lang) ?? 'Parking'),
    ];
    final tiles = all.take(3).toList();
    // A third of the row each, even when there are fewer, so the tiles keep
    // their square-ish shape; they share one height whatever their labels
    // wrap to.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: Space.sm),
            Expanded(
              child: i < tiles.length
                  ? FacilityTile(icon: tiles[i].$1, label: tiles[i].$2, width: double.infinity)
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.listing,
    required this.page,
    required this.onPage,
    required this.onOpen,
    this.heroTag,
    this.onMap,
    this.pillsKey,
  });
  final Listing listing;
  final String? heroTag;

  /// Scrolls to the map, from the pill on the photo.
  final VoidCallback? onMap;

  /// The row of pills on the photo, for the listing's tour.
  final Key? pillsKey;

  /// The first photo carries the card's tag; the rest their own, so each
  /// flies into the full-screen viewer and back.
  static String tagFor(Listing l, int i, String? cardTag) => i == 0 && cardTag != null ? cardTag : 'media-${l.id}-$i';
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final media = listing.media;
    final width = MediaQuery.sizeOf(context).width;
    if (media.isEmpty) return ListingImage(url: null, semanticLabel: t.noPhotos);
    final videos = media.where((m) => m.isVideo).length;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: media.length,
          onPageChanged: onPage,
          itemBuilder: (context, i) {
            final m = media[i];
            return GestureDetector(
              onTap: () => onOpen(i),
              child: m.isVideo
                  ? _VideoTile(label: t.detailsVideo)
                  : Hero(
                      tag: tagFor(listing, i, heroTag),
                      transitionOnUserGestures: true,
                      flightShuttleBuilder: _GalleryPhoto.shuttle,
                      child: _GalleryPhoto(
                        child: ListingImage(
                          url: m.url,
                          greyscale: listing.isClosed,
                          decodeWidth: width,
                          decodeHeight: _DetailsState._galleryHeight(MediaQuery.sizeOf(context)),
                          semanticLabel: listing.title(context.lang),
                        ),
                      ),
                    ),
            );
          },
        ),
        // A scrim at the top so the back and share buttons read on any photo.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Colors.black.withValues(alpha: 0.22), Colors.transparent],
              ),
            ),
          ),
        ),
        // Facts about what is behind the photo, as white pills along its
        // bottom edge: which photo this is, the clips, and the map.
        Positioned(
          bottom: Space.md,
          left: Space.sm,
          right: Space.sm,
          child: Center(
            child: Wrap(
              key: pillsKey,
              spacing: Space.xs,
              runSpacing: Space.xs,
              alignment: WrapAlignment.center,
              children: [
                if (media.length > 1)
                  _GalleryPill(
                    icon: Icons.photo_library_rounded,
                    label: t.detailsMediaPosition(page + 1, media.length),
                    onTap: () => onOpen(page),
                  ),
                if (videos > 0)
                  _GalleryPill(
                    icon: Icons.play_circle_rounded,
                    label: '$videos',
                    semanticLabel: t.detailsVideo,
                    onTap: () => onOpen(media.indexWhere((m) => m.isVideo)),
                  ),
                if (onMap != null) _GalleryPill(icon: Icons.map_rounded, label: t.detailsMapPill, onTap: onMap!),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A gallery photo, rounded like the gallery, also while it flies.
class _GalleryPhoto extends StatelessWidget {
  const _GalleryPhoto({required this.child});
  final Widget child;

  static const double radius = Radii.xl + 4;

  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);

  /// Arriving from a card, the photo that flies is the card's own, which is
  /// already decoded, so the flight never shows a blank placeholder; its
  /// corners round out from the card's to the gallery's on the way. Every
  /// other flight (to and from the full-screen viewer, back to a card) is
  /// the usual one.
  static Widget shuttle(
    BuildContext flight,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext from,
    BuildContext to,
  ) {
    final fromHero = from.widget as Hero;
    final toHero = to.widget as Hero;
    if (direction == HeroFlightDirection.push && toHero.child is _GalleryPhoto && fromHero.child is! _GalleryPhoto) {
      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) => ClipRRect(
          borderRadius: BorderRadius.circular(lerpDouble(Radii.lg, radius, animation.value)!),
          child: child,
        ),
        child: fromHero.child,
      );
    }
    return toHero.child;
  }
}

/// A white pill on the photo: an icon and a short fact; tappable.
class _GalleryPill extends StatelessWidget {
  const _GalleryPill({required this.icon, required this.label, required this.onTap, this.semanticLabel});
  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF16201D);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: Radii.tile,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.tile,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: ink),
                const SizedBox(width: Space.iconGap),
                Text(label, style: context.type.pill.copyWith(color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101614),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
          ),
          const SizedBox(height: Space.xs),
          Text(label, style: context.text.labelLarge?.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

/// The facts as a grouped list: label on the start side, value on the end.
class _Specs extends StatelessWidget {
  const _Specs({required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final lang = context.lang;
    final rows = <(IconData, String, String)>[
      (
        propertyTypeIcon(listing.propertyType),
        t.specType,
        Market.type(listing.propertyType)?.label(lang) ?? listing.propertyType,
      ),
      (Icons.sell_outlined, t.specDeal, listing.isRent ? t.badgeForRent : t.badgeForSale),
      // Bedrooms, bathrooms and size are the tiles above; zero counts and
      // land beside a built area are said here.
      if (listing.bedrooms == 0) (Icons.bed_outlined, t.specBeds, '0'),
      if (listing.landSqm != null && listing.areaSqm != null)
        (Icons.landscape_outlined, t.specLand, Fmt.area(listing.landSqm!, lang: lang)),
      if (listing.yearBuilt != null) (Icons.event_outlined, t.specYear, '${listing.yearBuilt}'),
      if (listing.updatedAt != null && listing.updatedAt!.difference(listing.createdAt).inHours > 1)
        (Icons.update_rounded, t.specUpdated, Fmt.date(listing.updatedAt!, lang: lang))
      else
        (Icons.schedule_rounded, t.specListed, Fmt.date(listing.createdAt, lang: lang)),
    ];
    return GroupedSection(
      children: [for (final (icon, label, value) in rows) GroupedTile(icon: icon, title: label, value: value)],
    );
  }
}

/// Amenities in two or three quiet columns: icon and name, no chip borders.
class _Amenities extends StatelessWidget {
  const _Amenities({required this.ids});
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final a in ids)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 10),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.tile),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(amenityIcon(a), size: 18, color: c.ink),
                const SizedBox(width: Space.xs),
                Flexible(child: Text(Market.amenity(a)?.label(lang) ?? a, style: context.text.labelMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final place = listing.place(lang);
    if (!listing.hasCoordinates) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (place.isNotEmpty) Text(place, style: context.text.bodyLarge),
          const SizedBox(height: Space.xs),
          Text(t.detailsNoLocation, style: context.text.bodySmall),
        ],
      );
    }
    final exact = listing.isExactLocation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: Radii.card,
          child: SizedBox(
            height: 180,
            child: LocationPreview(lat: listing.lat!, lng: listing.lng!, exact: exact),
          ),
        ),
        const SizedBox(height: Space.sm),
        // The street address is published only alongside an exact pin.
        if (exact && (listing.address?.trim().isNotEmpty ?? false)) ...[
          Text(listing.address!, style: context.text.bodyLarge),
          const SizedBox(height: Space.xs),
        ] else if (place.isNotEmpty) ...[
          Text(place, style: context.text.bodyLarge),
          const SizedBox(height: Space.xs),
        ],
        NoticeLine(
          icon: exact ? Icons.push_pin_outlined : Icons.blur_circular_rounded,
          text: exact ? t.detailsExactLocation : t.detailsApproxLocation,
          tone: c.emerald,
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () => openInMaps(listing.lat!, listing.lng!, listing.title(lang)),
              icon: const Icon(Icons.map_outlined, size: 20),
              label: Text(t.detailsOpenInMaps),
            ),
            // Only at an exact pin: at an approximate one, Street View would
            // show a street the property may not be on.
            if (exact)
              OutlinedButton.icon(
                onPressed: () => openStreetView(listing.lat!, listing.lng!),
                icon: const Icon(Icons.streetview_rounded, size: 20),
                label: Text(t.detailsStreetView),
              ),
          ],
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.listing, required this.enquiriesOpen, this.onWhatsApp, this.onCall});
  final Listing listing;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;
  final bool enquiriesOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final phone = listing.payload.contact.phone;
    Future<void> copy() async {
      final messenger = ScaffoldMessenger.of(context);
      await Clipboard.setData(ClipboardData(text: phone));
      unawaited(HapticFeedback.lightImpact());
      messenger.showSnackBar(SnackBar(content: Text(t.detailsNumberCopied), duration: const Duration(seconds: 2)));
    }

    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                child: Icon(Icons.person_rounded, color: c.inkMuted, size: 28),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listing.verified ? t.detailsVerifiedListing : t.detailsOwnerListing,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium,
                          ),
                        ),
                        if (listing.verified) ...[
                          const SizedBox(width: Space.xxs),
                          Icon(Icons.verified_rounded, size: 17, color: c.emerald),
                        ],
                      ],
                    ),
                    if (phone.isNotEmpty)
                      // Tap the number to copy it.
                      Tooltip(
                        message: t.detailsCopyNumber,
                        child: InkWell(
                          onTap: copy,
                          borderRadius: Radii.chip,
                          child: Text(
                            phone,
                            textDirection: TextDirection.ltr,
                            style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                          ),
                        ),
                      )
                    else
                      Text(t.detailsNoPhone, style: context.text.bodySmall),
                  ],
                ),
              ),
              if (onWhatsApp != null) ...[
                const SizedBox(width: Space.xs),
                _RoundAction(icon: Icons.chat_rounded, label: t.detailsWhatsApp, onTap: onWhatsApp!),
              ],
              if (onCall != null) ...[
                const SizedBox(width: Space.xs),
                _RoundAction(icon: Icons.call_rounded, label: t.detailsCall, onTap: onCall!),
              ],
            ],
          ),
          if (!enquiriesOpen) ...[
            const SizedBox(height: Space.sm),
            Text(t.inquiryClosed, style: context.text.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// A round dark button: chat, call.
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: c.forest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 21, color: c.onForest)),
          ),
        ),
      ),
    );
  }
}

/// The price, and the one thing to do next.
class _StickyBar extends StatelessWidget {
  const _StickyBar({required this.listing, this.onCall, this.onEnquire, this.actionKey});
  final Listing listing;
  final VoidCallback? onCall;
  final VoidCallback? onEnquire;

  /// The button, for the listing's tour.
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final (label, action) = onEnquire != null ? (t.detailsEnquire, onEnquire!) : (t.detailsCall, onCall!);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl + 2)),
        border: Border(top: BorderSide(color: c.border)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      padding: Layout.inset(context, top: Space.md, bottom: Space.sm),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: listing.isRent ? t.badgeForRent : t.badgeForSale,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    Fmt.price(listing.priceJod, lang: lang, rent: listing.isRent),
                    style: context.type.priceLarge,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            FilledButton(
              key: actionKey,
              onPressed: action,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 54),
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                shape: const RoundedRectangleBorder(borderRadius: Radii.field),
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// The owner's description, cut at three lines with "Read more" on the last
/// one; the whole paragraph toggles it.
class _ReadMore extends StatefulWidget {
  const _ReadMore({required this.text, required this.open, required this.onToggle});
  final String text;
  final bool open;
  final VoidCallback onToggle;

  static const lines = 3;

  @override
  State<_ReadMore> createState() => _ReadMoreState();
}

class _ReadMoreState extends State<_ReadMore> {
  // The cut depends only on the text, the width, the text size and the label.
  (String, double, TextScaler, String)? _for;
  String? _cut;

  /// The longest start of the text that leaves room for "… Read more" in
  /// [_ReadMore.lines] lines, or null when it all fits.
  String? _measure(
    TextStyle style,
    TextStyle moreStyle,
    double width,
    TextDirection dir,
    TextScaler scaler,
    String more,
  ) {
    final key = (widget.text, width, scaler, more);
    if (_for == key) return _cut;
    bool fits(String text, {String? tail}) {
      final tp = TextPainter(
        text: TextSpan(
          style: style,
          children: [
            TextSpan(text: text),
            if (tail != null) TextSpan(text: tail, style: moreStyle),
          ],
        ),
        textDirection: dir,
        textScaler: scaler,
        maxLines: _ReadMore.lines,
      )..layout(maxWidth: width);
      final ok = !tp.didExceedMaxLines;
      tp.dispose();
      return ok;
    }

    String? cut;
    if (!fits(widget.text)) {
      final chars = widget.text.characters.toList();
      var lo = 0;
      var hi = chars.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fits('${chars.take(mid).join().trimRight()}… ', tail: more)) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      cut = '${chars.take(lo).join().trimRight()}… ';
    }
    _for = key;
    _cut = cut;
    return cut;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final dir = directionOf(widget.text, Directionality.of(context));
    // The owner's paragraph in its own script's face.
    final style = styleForScript(context.text.bodyMedium!.copyWith(color: c.inkMuted), rtl: dir == TextDirection.rtl);
    final moreStyle = style.copyWith(color: c.ink, fontWeight: FontWeight.w600);
    return LayoutBuilder(
      builder: (context, box) {
        final cut = _measure(style, moreStyle, box.maxWidth, dir, MediaQuery.textScalerOf(context), t.detailsReadMore);
        if (cut == null) return Text(widget.text, style: style, textDirection: dir);
        final open = widget.open;
        return Semantics(
          button: true,
          hint: open ? t.detailsReadLess : t.detailsReadMore,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggle,
            child: AnimatedSize(
              duration: Motion.of(context, Motion.normal),
              curve: Motion.standard,
              alignment: AlignmentDirectional.topStart,
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    TextSpan(text: open ? '${widget.text}  ' : cut),
                    TextSpan(text: open ? t.detailsReadLess : t.detailsReadMore, style: moreStyle),
                  ],
                ),
                textDirection: dir,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OwnerBanner extends StatelessWidget {
  const _OwnerBanner({required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.gold.withValues(alpha: 0.12), c.surface),
        borderRadius: Radii.field,
        border: Border.all(color: c.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, color: c.gold),
          const SizedBox(width: Space.xs),
          Expanded(child: Text(t.detailsYourListing, style: context.text.titleSmall)),
          TextButton(onPressed: () => context.push(Routes.editListing(listing.id)), child: Text(t.actionEdit)),
          TextButton(onPressed: () => context.push(Routes.dashboard), child: Text(t.detailsManage)),
        ],
      ),
    );
  }
}

class _Similar extends ConsumerWidget {
  const _Similar({required this.listing});
  final Listing listing;

  /// The listing's own facts as a brief, so "similar" means the same kind of
  /// place in the same area at about the same price — every part of which the
  /// reader sees as a chip and can remove.
  SearchConstraints _brief() {
    final step = listing.isRent ? 50 : 5000;
    final price = listing.priceJod;
    return SearchConstraints(
      deal: listing.isRent ? 'rent' : 'sale',
      city: listing.cityId,
      hood: listing.neighborhoodId,
      type: listing.propertyType.isEmpty ? null : listing.propertyType,
      beds: listing.bedrooms,
      budgetMax: price > 0 ? ((price * 1.15) / step).ceil() * step : null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final inset = Layout.inset(context);
    final rows =
        ref
            .watch(
              similarListingsProvider((
                id: listing.id,
                deal: listing.deal,
                city: listing.cityId,
                type: listing.propertyType,
              )),
            )
            .value ??
        const <Listing>[];
    final width = (MediaQuery.sizeOf(context).width * 0.7).clamp(220.0, 320.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: inset.copyWith(top: Space.lg, bottom: Space.lg),
          child: const Divider(),
        ),
        SectionHeader(
          padding: EdgeInsets.symmetric(horizontal: inset.left),
          title: t.detailsSimilar,
          action: t.detailsFindSimilar,
          onAction: () {
            final label = t.detailsSimilarTurn(listing.title(context.lang));
            unawaited(ref.read(aiSearchProvider.notifier).setConstraintsFresh(_brief(), label: label));
            context.go(Routes.aiSearch);
          },
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          SizedBox(
            height: PropertyCard.heightFor(context, width),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: inset.left),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, i) => PropertyCard(
                listing: rows[i],
                width: width,
                heroTag: 'similar-${listing.id}-${rows[i].id}',
                onTap: () => openProperty(context, rows[i], hero: 'similar-${listing.id}-${rows[i].id}'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    // The page's own shape, so nothing jumps when it arrives: the inset photo,
    // the pills, title and place, then three facility tiles.
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _DetailsState._photoInset,
              _DetailsState._photoInset,
              _DetailsState._photoInset,
              0,
            ),
            child: Skeleton(height: _DetailsState._galleryHeight(size), radius: Radii.xl + 4),
          ),
          Padding(
            padding: Layout.inset(context, top: Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Skeleton(width: 84, height: 36, radius: Radii.md - 2),
                    Spacer(),
                    Skeleton(width: 92, height: 36, radius: Radii.md - 2),
                  ],
                ),
                const SizedBox(height: Space.md),
                const Skeleton.line(width: 240, height: 28),
                const SizedBox(height: Space.sm),
                const Skeleton.line(width: 150, height: 16),
                const SizedBox(height: Space.xl),
                const Skeleton.line(width: 110, height: 22),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: Space.sm),
                      const Expanded(child: Skeleton(height: 100, radius: Radii.lg)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
