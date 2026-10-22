import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/segmented_pill.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/account_models.dart';
import '../../shared/repositories/account_repositories.dart';
import '../../shared/services/supabase_providers.dart';
import '../../shared/widgets/property_card.dart';
import '../ai_search/domain/portal_links.dart';
import '../ai_search/presentation/ai_search_controller.dart';
import '../ai_search/presentation/constraint_chips.dart';
import '../property_details/property_details_screen.dart';
import '../saved_searches/saved_searches_providers.dart';
import 'favorites_controller.dart';

enum _Tab { properties, searches }

class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.initialTab, this.tabToken});
  final String? initialTab;

  /// Changes with every link that names a tab, so following "Saved searches"
  /// from Profile switches tabs even when Saved is already open on the other.
  final String? tabToken;

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  late _Tab _tab = _fromQuery(widget.initialTab) ?? _Tab.properties;

  static _Tab? _fromQuery(String? q) => switch (q) {
    'searches' => _Tab.searches,
    'properties' => _Tab.properties,
    _ => null,
  };

  @override
  void didUpdateWidget(SavedScreen old) {
    super.didUpdateWidget(old);
    final asked = _fromQuery(widget.initialTab);
    if (asked != null && (widget.initialTab != old.initialTab || widget.tabToken != old.tabToken)) {
      setState(() => _tab = asked);
    }
  }

  Future<void> _refresh() async {
    if (_tab == _Tab.properties) {
      await ref.read(favoritesProvider.notifier).sync();
      ref.invalidate(favoriteListingsProvider);
    } else {
      ref.invalidate(savedSearchesProvider);
      await ref.read(savedSearchesProvider.future).catchError((Object _) => const <SavedSearch>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inset = Layout.inset(context, max: Layout.grid);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final pillHeight = 34 * scaler.scale(1) < 40 ? 40.0 : 34 * scaler.scale(1);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + pillHeight + Space.md,
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(
              title: l.savedTitle,
              contentMax: Layout.grid,
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(pillHeight + Space.md),
                child: Padding(
                  padding: inset.copyWith(bottom: Space.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SegmentedPill<_Tab>(
                      expand: !Layout.isWide(context),
                      value: _tab,
                      onChanged: (t) => setState(() => _tab = t),
                      segments: [
                        PillSegment(value: _Tab.properties, label: l.savedProperties),
                        PillSegment(value: _Tab.searches, label: l.savedSearches),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ...switch (_tab) {
              _Tab.properties => _savedProperties(context),
              _Tab.searches => _savedSearches(context),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _savedProperties(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final fav = ref.watch(favoritesProvider);
    final async = ref.watch(favoriteListingsProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final inset = Layout.inset(context, max: Layout.grid);

    final notice = switch (fav.mode) {
      FavoritesMode.device when !signedIn => NoticeLine(icon: Icons.phone_iphone_rounded, text: l.savedDeviceOnly),
      FavoritesMode.deviceFallback => NoticeLine(icon: Icons.cloud_off_outlined, text: l.savedSyncUnavailable),
      _ => null,
    };
    final noticeSliver = notice == null
        ? null
        : SliverPadding(
            padding: Layout.inset(context, max: Layout.grid, top: Space.xs, bottom: Space.md),
            sliver: SliverToBoxAdapter(child: notice),
          );

    if (fav.ids.isEmpty) {
      return [
        ?noticeSliver,
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.favorite_border_rounded,
            title: l.savedEmptyTitle,
            body: l.savedEmptyBody,
            action: OutlinedButton(onPressed: () => context.go(Routes.explore), child: Text(l.tabExplore)),
          ),
        ),
      ];
    }

    return async.when(
      skipLoadingOnReload: true,
      data: (data) => [
        ?noticeSliver,
        SliverPadding(
          padding: inset.copyWith(top: Space.xs),
          sliver: SliverCardList(
            itemCount: data.listings.length,
            itemBuilder: (context, i) {
              final listing = data.listings[i];
              return Reveal(
                index: i,
                id: 'saved-${listing.id}',
                child: PropertyCard(
                  key: ValueKey(listing.id),
                  listing: listing,
                  heroTag: 'saved-${listing.id}',
                  onTap: () => openProperty(context, listing, hero: 'saved-${listing.id}'),
                ),
              );
            },
          ),
        ),
        if (data.missing.isNotEmpty)
          SliverPadding(
            padding: Layout.inset(context, max: Layout.grid, top: Space.xl),
            sliver: SliverToBoxAdapter(
              child: GroupedSection(
                children: [
                  for (final id in data.missing)
                    GroupedTile(
                      icon: Icons.hide_image_outlined,
                      title: l.savedListingGone,
                      subtitle: id.substring(0, 8),
                      trailing: IconButton(
                        tooltip: l.a11yUnsave,
                        icon: Icon(Icons.close_rounded, color: c.inkMuted),
                        onPressed: () => unawaited(ref.read(favoritesProvider.notifier).toggle(id)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: Space.xxl + MediaQuery.paddingOf(context).bottom)),
      ],
      loading: () => [
        SliverPadding(
          padding: inset.copyWith(top: Space.xs, bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
          sliver: SliverCardList(itemCount: 2, itemBuilder: (_, _) => const PropertyCardSkeleton()),
        ),
      ],
      error: (e, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(error: e, onRetry: () => ref.invalidate(favoriteListingsProvider)),
        ),
      ],
    );
  }

  List<Widget> _savedSearches(BuildContext context) {
    final l = context.l10n;
    if (!ref.watch(isSignedInProvider)) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.bookmarks_outlined,
            title: l.savedSearchesEmptyTitle,
            body: l.savedSearchesSignIn,
            action: FilledButton(
              onPressed: () => context.push(Routes.withNext(Routes.signIn, '${Routes.saved}?tab=searches')),
              child: Text(l.actionSignIn),
            ),
          ),
        ),
      ];
    }
    final inset = Layout.inset(context, max: Layout.grid);
    return ref
        .watch(savedSearchesProvider)
        .when(
          data: (rows) => rows.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.bookmarks_outlined,
                      title: l.savedSearchesEmptyTitle,
                      body: l.savedSearchesEmptyBody,
                      action: OutlinedButton(onPressed: () => context.go(Routes.aiSearch), child: Text(l.tabAiSearch)),
                    ),
                  ),
                ]
              : [
                  SliverPadding(
                    padding: inset.copyWith(top: Space.xs, bottom: Space.xxl + MediaQuery.paddingOf(context).bottom),
                    sliver: SliverCardList(
                      rowGap: Space.sm,
                      columnGap: Space.sm,
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _SavedSearchCard(key: ValueKey(rows[i].id), search: rows[i]),
                    ),
                  ),
                ],
          loading: () => [
            SliverPadding(
              padding: inset.copyWith(top: Space.xs),
              sliver: const SliverToBoxAdapter(
                child: Column(
                  children: [
                    Skeleton(height: 110),
                    SizedBox(height: Space.sm),
                    Skeleton(height: 110),
                  ],
                ),
              ),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(error: e, onRetry: () => ref.invalidate(savedSearchesProvider)),
            ),
          ],
        );
  }
}

/// A saved brief. The whole card runs it again; removing it can be undone.
class _SavedSearchCard extends ConsumerWidget {
  const _SavedSearchCard({super.key, required this.search});
  final SavedSearch search;

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    ref.read(aiSearchProvider.notifier).reset();
    context.go(Routes.aiSearch);
    await ref.read(aiSearchProvider.notifier).setConstraintsFresh(search.constraints, label: search.label);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final failText = context.failureMessage;
    final repo = ref.read(savedSearchesRepositoryProvider);
    // The card is gone by the time Undo is pressed, and its ref with it.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await repo.delete(search.id);
      container.invalidate(savedSearchesProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l.savedSearchDeleted),
            action: SnackBarAction(
              label: l.actionUndo,
              onPressed: () async {
                try {
                  await repo.create(search.label, search.constraints);
                  container.invalidate(savedSearchesProvider);
                } on Object catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(failText(e))));
                }
              },
            ),
          ),
        );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failText(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final chips = constraintChips(context, search.constraints);
    final title = search.label.isEmpty ? PortalLinks.describe(search.constraints, context.lang) : search.label;
    return Material(
      color: c.surfaceMuted,
      shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _run(context, ref),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Space.md, Space.sm, Space.xxs, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                          const SizedBox(height: Space.hair),
                          Text(Fmt.date(search.createdAt, lang: context.lang), style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.actionDelete,
                    onPressed: () => _delete(context, ref),
                    icon: Icon(Icons.delete_outline_rounded, color: c.inkMuted, size: 22),
                  ),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: Space.sm),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final ch in chips.take(6)) TagChip(label: ch.label, icon: ch.icon)],
                  ),
                ),
              ],
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: c.emerald),
                  const SizedBox(width: Space.iconGap),
                  Text(l.savedSearchRun, style: context.text.labelLarge?.copyWith(color: c.emerald)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
