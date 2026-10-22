import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/listing_image.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/user_text.dart';
import '../../features/favorites/favorites_controller.dart';
import '../models/listing.dart';
import '../reference/market_data.dart';
import 'pickers.dart';

/// The heart. Saves immediately, rolls back with a message if the write fails.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.listingId, this.onImage = true, this.size = 22, this.squared = false});

  final String listingId;

  /// On a photograph the heart sits on a frosted disc so it reads on any image.
  final bool onImage;
  final double size;

  /// A rounded square, beside the other buttons over a listing's photos.
  final bool squared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(favoritesProvider.select((s) => s.contains(listingId)));
    final c = context.colors;
    final l = context.l10n;
    final icon = AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
      child: Icon(
        saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        key: ValueKey(saved),
        size: size,
        color: onImage ? const Color(0xFF16201D) : c.ink,
      ),
    );
    return Semantics(
      button: true,
      toggled: saved,
      label: saved ? l.a11yUnsave : l.a11ySave,
      child: InkResponse(
        radius: 26,
        onTap: () async {
          unawaited(HapticFeedback.lightImpact());
          final messenger = ScaffoldMessenger.of(context);
          final failText = context.failureMessage;
          try {
            final nowSaved = await ref.read(favoritesProvider.notifier).toggle(listingId);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(nowSaved ? l.savedAdded : l.savedRemoved), duration: const Duration(seconds: 2)),
              );
          } on Object catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(failText(e))));
          }
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          width: squared ? 48 : (onImage ? 40 : 44),
          height: squared ? 48 : (onImage ? 40 : 44),
          alignment: Alignment.center,
          decoration: !onImage
              ? BoxDecoration(borderRadius: BorderRadius.circular(14))
              : squared
              ? BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                )
              : const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: icon,
        ),
      ),
    );
  }
}

/// Sale / rent / sold / rented / verified, as a small label.
class ListingBadge extends StatelessWidget {
  const ListingBadge({super.key, required this.label, required this.background, required this.foreground, this.icon});

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: foreground), const SizedBox(width: Space.xxs)],
          Text(label, style: context.type.badge.copyWith(color: foreground)),
        ],
      ),
    );
  }

  static Widget forListing(BuildContext context, Listing l) {
    final t = context.l10n;
    final c = context.colors;
    if (l.status == ListingStatus.sold) {
      return ListingBadge(label: t.badgeSold, background: c.red, foreground: Colors.white);
    }
    if (l.status == ListingStatus.rented) {
      return ListingBadge(label: t.badgeRented, background: c.red, foreground: Colors.white);
    }
    return ListingBadge(
      label: l.isRent ? t.badgeForRent : t.badgeForSale,
      background: Colors.white.withValues(alpha: 0.94),
      foreground: const Color(0xFF123C34),
    );
  }
}

/// Bedrooms · bathrooms · area, each only when the listing has it.
class ListingFacts extends StatelessWidget {
  const ListingFacts({super.key, required this.listing, this.dense = false});
  final Listing listing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    final t = context.l10n;
    final style = (dense ? context.text.labelSmall : context.text.labelMedium)?.copyWith(color: c.inkMuted);
    final facts = <(IconData, String, String)>[
      if (listing.bedrooms case final b? when b > 0) (Icons.bed_outlined, '$b', t.a11yBeds(b)),
      if (listing.bathrooms case final b? when b > 0) (Icons.bathtub_outlined, '$b', t.a11yBaths(b)),
      if (listing.areaSqm case final a? when a > 0)
        (Icons.square_foot_rounded, Fmt.area(a, lang: lang), Fmt.area(a, lang: lang)),
      if (listing.areaSqm == null && listing.landSqm != null)
        (Icons.landscape_outlined, Fmt.area(listing.landSqm!, lang: lang), Fmt.area(listing.landSqm!, lang: lang)),
    ];
    if (facts.isEmpty) {
      final type = Market.type(listing.propertyType)?.label(lang) ?? listing.propertyType;
      return Text(type, style: style);
    }
    return Wrap(
      spacing: dense ? Space.sm : Space.md,
      runSpacing: 4,
      children: [
        for (final (icon, value, label) in facts)
          Semantics(
            label: label,
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: dense ? 15 : 17, color: c.inkFaint),
                const SizedBox(width: Space.xxs),
                Text(value, style: style),
              ],
            ),
          ),
      ],
    );
  }
}

/// The listing card: a soft grey card holding the photo inset, white pills
/// on the photo, a white panel with the title and place, then the counts and
/// the price. Used in Explore, Home, Saved and similar listings.
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.listing, required this.onTap, this.width, this.heroTag});

  final Listing listing;
  final VoidCallback onTap;
  final double? width;
  final String? heroTag;

  /// How tall a card of [width] is, for horizontal rows that need a height.
  static double heightFor(BuildContext context, double width) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    return (width - 2 * Space.xs) * 10.5 / 16 + 2 * Space.xs + Space.xs + 172 * scale;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    final t = context.l10n;
    final place = listing.place(lang);
    final cardWidth = width ?? MediaQuery.sizeOf(context).width;
    final image = ListingImage(
      url: listing.coverUrl,
      greyscale: listing.isClosed,
      decodeWidth: cardWidth - 2 * Space.xs,
      decodeHeight: (cardWidth - 2 * Space.xs) * 10.5 / 16,
    );
    final type = Market.type(listing.propertyType);
    // Hugs its content even in a row that hands it a fixed height.
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: width,
        child: Semantics(
          container: true,
          button: true,
          label: '${listing.title(lang)}, ${Fmt.price(listing.priceJod, lang: lang, rent: listing.isRent)}, $place',
          child: Pressable(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.xl),
            child: Container(
              padding: const EdgeInsets.all(Space.xs),
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.xl)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10.5,
                    child: ClipRRect(
                      borderRadius: Radii.card,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          heroTag == null ? image : Hero(tag: heroTag!, child: image),
                          PositionedDirectional(
                            top: Space.sm,
                            start: Space.sm,
                            child: listing.isClosed
                                ? ListingBadge.forListing(context, listing)
                                : InfoPill(
                                    icon: propertyTypeIcon(listing.propertyType),
                                    label: type?.label(lang) ?? (listing.isRent ? t.badgeForRent : t.badgeForSale),
                                  ),
                          ),
                          PositionedDirectional(
                            top: Space.xs,
                            end: Space.xs,
                            child: FavoriteButton(listingId: listing.id),
                          ),
                          if (listing.verified)
                            PositionedDirectional(
                              bottom: Space.sm,
                              start: Space.sm,
                              child: InfoPill(icon: Icons.verified_rounded, label: t.badgeVerified, dense: true),
                            ),
                          if (listing.media.length > 1)
                            PositionedDirectional(
                              bottom: Space.sm,
                              end: Space.sm,
                              child: InfoPill(
                                icon: Icons.photo_library_outlined,
                                label: '${listing.media.length}',
                                dense: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Container(
                    padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
                    decoration: BoxDecoration(color: c.surface, borderRadius: Radii.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: UserText(
                                listing.title(lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.titleMedium,
                              ),
                            ),
                            const SizedBox(width: Space.xs),
                            _DealTag(listing: listing),
                          ],
                        ),
                        if (place.isNotEmpty) ...[
                          const SizedBox(height: Space.hair),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 16, color: c.inkMuted),
                              const SizedBox(width: Space.hair),
                              Expanded(
                                child: Text(
                                  place,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                                ),
                              ),
                            ],
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Space.sm),
                          child: Divider(height: 1, color: c.border),
                        ),
                        Row(
                          children: [
                            Expanded(child: _SpecPills(listing: listing)),
                            const SizedBox(width: Space.xs),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  Fmt.price(listing.priceJod, lang: lang, rent: listing.isRent),
                                  style: context.type.price.copyWith(
                                    color: listing.isClosed ? c.inkMuted : c.ink,
                                    decoration: listing.isClosed ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                            ),
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
      ),
    );
  }
}

/// "For sale" / "For rent" as a quiet tag beside the title.
class _DealTag extends StatelessWidget {
  const _DealTag({required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    final rent = listing.isRent;
    final colour = rent ? const Color(0xFFD9B25E) : c.emerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.iconGap),
          Text(rent ? t.badgeForRent : t.badgeForSale, style: context.type.pill),
        ],
      ),
    );
  }
}

/// Bedrooms, bathrooms and area as outlined pills; only what the listing has.
class _SpecPills extends StatelessWidget {
  const _SpecPills({required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final lang = context.lang;
    final pills = <Widget>[
      if (listing.bedrooms case final b? when b > 0)
        SpecPill(icon: Icons.bed_outlined, label: '$b', semanticLabel: t.a11yBeds(b)),
      if (listing.bathrooms case final b? when b > 0)
        SpecPill(icon: Icons.bathtub_outlined, label: '$b', semanticLabel: t.a11yBaths(b)),
      if ((listing.bedrooms ?? 0) == 0 && (listing.areaSqm ?? listing.landSqm) != null)
        SpecPill(
          icon: Icons.square_foot_rounded,
          label: Fmt.area((listing.areaSqm ?? listing.landSqm)!, lang: lang),
        ),
    ];
    if (pills.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: pills);
  }
}

/// The small card of the reference's second row, two to a line: the photo
/// inset in a grey card with the type and the heart on it, then the title,
/// the place and the price.
class PropertyCardCompact extends StatelessWidget {
  const PropertyCardCompact({super.key, required this.listing, required this.onTap, this.heroTag});

  final Listing listing;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    final t = context.l10n;
    final place = listing.place(lang);
    final type = Market.type(listing.propertyType);
    final price = Fmt.price(listing.priceJod, lang: lang, rent: listing.isRent);
    final image = ListingImage(
      url: listing.coverUrl,
      greyscale: listing.isClosed,
      decodeWidth: MediaQuery.sizeOf(context).width / 2,
      decodeHeight: MediaQuery.sizeOf(context).width / 2 / 1.08,
    );
    return Semantics(
      container: true,
      button: true,
      label: '${listing.title(lang)}, $price, $place',
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg + 2),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.lg + 2)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1.08,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.lg - 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      heroTag == null ? image : Hero(tag: heroTag!, child: image),
                      PositionedDirectional(
                        top: Space.xs,
                        start: Space.xs,
                        child: listing.isClosed
                            ? ListingBadge.forListing(context, listing)
                            : InfoPill(
                                icon: propertyTypeIcon(listing.propertyType),
                                label: type?.label(lang) ?? (listing.isRent ? t.badgeForRent : t.badgeForSale),
                                dense: true,
                              ),
                      ),
                      PositionedDirectional(top: 4, end: 4, child: FavoriteButton(listingId: listing.id, size: 18)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.sm, Space.xs, Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserText(
                      listing.title(lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: Space.hair),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: c.inkMuted),
                          const SizedBox(width: Space.hair),
                          Expanded(
                            child: Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall?.copyWith(color: c.inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Space.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        price,
                        style: context.type.priceSmall.copyWith(
                          color: listing.isClosed ? c.inkMuted : c.ink,
                          decoration: listing.isClosed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact horizontal row, for dashboards and dense lists.
class PropertyRow extends StatelessWidget {
  const PropertyRow({
    super.key,
    required this.listing,
    required this.onTap,
    this.trailing,
    this.footer,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
  });

  final Listing listing;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? footer;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return Pressable(
      onTap: onTap,
      borderRadius: Radii.field,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: Radii.field,
                  child: SizedBox(
                    width: 96,
                    height: 80,
                    child: ListingImage(url: listing.coverUrl, greyscale: listing.isClosed, decodeWidth: 96),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserText(
                        listing.title(lang),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: Space.hair),
                      Text(
                        Fmt.price(listing.priceJod, lang: lang, rent: listing.isRent),
                        style: context.type.priceSmall,
                      ),
                      if (listing.place(lang).isNotEmpty)
                        Text(
                          listing.place(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (footer != null) ...[const SizedBox(height: Space.xs), footer!],
          ],
        ),
      ),
    );
  }
}
