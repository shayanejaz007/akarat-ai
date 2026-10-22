import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/listing.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/services/preferences.dart';
import '../../shared/services/refresh.dart';

/// Buy or rent on Home, remembered between launches.
final homeDealProvider = NotifierProvider<HomeDeal, DealType>(HomeDeal.new);

class HomeDeal extends Notifier<DealType> {
  @override
  DealType build() => DealType.parse(ref.read(preferencesProvider).homeDeal);

  Future<void> set(DealType deal) async {
    state = deal;
    await ref.read(preferencesProvider).setHomeDeal(deal.name);
  }
}

/// The city Home is scoped to; null means all of Jordan.
final homeCityProvider = NotifierProvider<HomeCity, String?>(HomeCity.new);

class HomeCity extends Notifier<String?> {
  @override
  String? build() => ref.read(preferencesProvider).homeCity;

  Future<void> set(String? cityId) async {
    state = cityId;
    await ref.read(preferencesProvider).setHomeCity(cityId);
  }
}

final recentListingsProvider = FutureProvider.autoDispose<List<Listing>>((ref) {
  ref.watch(refreshTickProvider);
  return ref
      .watch(listingsRepositoryProvider)
      // Enough for the carousel and the grid of smaller cards under it.
      .recent(deal: ref.watch(homeDealProvider), cityId: ref.watch(homeCityProvider), limit: 16);
});

final featuredListingsProvider = FutureProvider.autoDispose<List<Listing>>((ref) {
  ref.watch(refreshTickProvider);
  return ref
      .watch(listingsRepositoryProvider)
      .featured(deal: ref.watch(homeDealProvider), cityId: ref.watch(homeCityProvider));
});
