import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../shared/models/listing.dart';
import '../../shared/repositories/favorites_repository.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/services/preferences.dart';
import '../../shared/services/supabase_providers.dart';

enum FavoritesMode {
  /// Signed out: kept on this device until the reader signs in.
  device,

  /// Signed in and stored in `public.favorites`, shared with every device.
  account,

  /// Signed in, but the account cannot store favourites yet because
  /// migration 0014 has not been applied. Kept on the device meanwhile.
  deviceFallback,
}

class FavoritesState {
  const FavoritesState({this.ids = const [], this.mode = FavoritesMode.device, this.syncing = false});

  /// Most recently saved first.
  final List<String> ids;
  final FavoritesMode mode;
  final bool syncing;

  bool contains(String id) => ids.contains(id);

  FavoritesState copyWith({List<String>? ids, FavoritesMode? mode, bool? syncing}) =>
      FavoritesState(ids: ids ?? this.ids, mode: mode ?? this.mode, syncing: syncing ?? this.syncing);
}

final favoritesProvider = NotifierProvider<FavoritesController, FavoritesState>(FavoritesController.new);

class FavoritesController extends Notifier<FavoritesState> {
  FavoritesRepository get _repo => ref.read(favoritesRepositoryProvider);
  Preferences get _prefs => ref.read(preferencesProvider);
  Future<void>? _running;
  bool _again = false;

  @override
  FavoritesState build() {
    ref.listen(currentUserProvider, (prev, next) {
      if (prev?.id != next?.id) unawaited(sync());
    });
    scheduleMicrotask(sync);
    return FavoritesState(ids: _prefs.localFavorites);
  }

  /// Reconciles with the account. Anything saved as a guest is carried into
  /// the account on sign-in, then cleared from the device, so the next person
  /// to use the phone signed out does not inherit it.
  ///
  /// Concurrent calls (launch, sign-in, pull to refresh) share one run, and a
  /// call that arrives mid-run queues exactly one more pass, so every caller
  /// awaits a result that reflects the session at the time it asked.
  Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = _loop();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
  }

  Future<void> _syncOnce() async {
    final signedIn = ref.read(currentUserProvider) != null;
    if (!signedIn) {
      state = FavoritesState(ids: _prefs.localFavorites);
      return;
    }
    state = state.copyWith(syncing: true);
    try {
      if (!await _repo.isAvailable()) {
        state = FavoritesState(ids: _prefs.localFavorites, mode: FavoritesMode.deviceFallback);
        return;
      }
      final local = _prefs.localFavorites;
      if (local.isNotEmpty) {
        await _repo.addAll(local);
        await _prefs.setLocalFavorites(const []);
      }
      state = FavoritesState(ids: await _repo.list(), mode: FavoritesMode.account);
    } on AppFailure {
      // Offline or the database is unreachable: keep what is on screen and
      // try again on the next sign-in or refresh.
      state = state.copyWith(syncing: false);
    }
  }

  /// Saves or unsaves immediately, then writes. If the write fails the change
  /// is rolled back and the failure is rethrown for the caller to show.
  /// Returns whether the listing is now saved.
  Future<bool> toggle(String id) async {
    final before = state;
    final saving = !before.contains(id);
    final next = saving ? [id, ...before.ids] : before.ids.where((x) => x != id).toList();
    state = before.copyWith(ids: next);
    try {
      if (before.mode == FavoritesMode.account) {
        if (saving) {
          await _repo.add(id);
        } else {
          await _repo.remove(id);
        }
      } else {
        await _prefs.setLocalFavorites(next);
      }
      return saving;
    } on Object {
      state = before;
      rethrow;
    }
  }
}

/// The saved listings themselves, in saved order. Ids whose listing is gone
/// (deleted, or hidden by its owner) are reported separately so the Saved tab
/// can say so instead of silently dropping them.
final favoriteListingsProvider = FutureProvider.autoDispose<({List<Listing> listings, List<String> missing})>((
  ref,
) async {
  final ids = ref.watch(favoritesProvider.select((s) => s.ids));
  if (ids.isEmpty) return (listings: const <Listing>[], missing: const <String>[]);
  final rows = await ref.read(listingsRepositoryProvider).byIds(ids);
  final found = {for (final r in rows) r.id};
  return (listings: rows, missing: ids.where((id) => !found.contains(id)).toList());
});
