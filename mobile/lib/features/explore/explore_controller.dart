import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/listing.dart';
import '../../shared/models/listing_filters.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/services/refresh.dart';

final exploreFiltersProvider = NotifierProvider<ExploreFilters, ListingFilters>(ExploreFilters.new);

class ExploreFilters extends Notifier<ListingFilters> {
  @override
  // Sale and rent together: the map shows both, told apart by colour.
  ListingFilters build() => const ListingFilters();

  void replace(ListingFilters next) {
    if (next != state) state = next;
  }
}

class ExploreState {
  const ExploreState({
    required this.items,
    required this.total,
    required this.page,
    this.loadingMore = false,
    this.moreError,
  });

  final List<Listing> items;
  final int total;
  final int page;
  final bool loadingMore;
  final Object? moreError;

  bool get hasMore => items.length < total;

  ExploreState copyWith({
    List<Listing>? items,
    int? total,
    int? page,
    bool? loadingMore,
    Object? moreError,
    bool clearError = false,
  }) => ExploreState(
    items: items ?? this.items,
    total: total ?? this.total,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: clearError ? null : (moreError ?? this.moreError),
  );
}

/// Pages of the marketplace for the current filters. Changing a filter
/// rebuilds from page 0; a page still in flight for the old filters is
/// discarded when it lands, so results never mix two searches.
final exploreProvider = AsyncNotifierProvider<ExploreController, ExploreState>(ExploreController.new);

class ExploreController extends AsyncNotifier<ExploreState> {
  int _generation = 0;

  @override
  Future<ExploreState> build() async {
    ref.watch(refreshTickProvider);
    final filters = ref.watch(exploreFiltersProvider);
    final gen = ++_generation;
    final page = await ref.read(listingsRepositoryProvider).browse(filters);
    if (gen != _generation) throw StateError('superseded');
    return ExploreState(items: page.items, total: page.total, page: 0);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore || state.isLoading) return;
    final gen = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await ref
          .read(listingsRepositoryProvider)
          .browse(ref.read(exploreFiltersProvider), page: current.page + 1);
      if (gen != _generation) return;
      // A listing published while scrolling shifts the pages by one; drop
      // the duplicate rather than showing it twice.
      final seen = {for (final l in current.items) l.id};
      state = AsyncData(
        ExploreState(
          items: [...current.items, ...next.items.where((l) => !seen.contains(l.id))],
          total: next.total,
          page: next.page,
        ),
      );
    } on Object catch (e) {
      if (gen != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false, moreError: e));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future.catchError((Object _) => const ExploreState(items: [], total: 0, page: 0));
  }
}

/// Every listing with a location that matches the filters, for the map.
final exploreMapProvider = FutureProvider.autoDispose<List<Listing>>((ref) {
  ref.watch(refreshTickProvider);
  final filters = ref.watch(exploreFiltersProvider);
  return ref.watch(listingsRepositoryProvider).mapListings(filters);
});
