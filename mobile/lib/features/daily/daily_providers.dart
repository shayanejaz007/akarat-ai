import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/daily_models.dart';
import '../../shared/models/listing.dart';
import '../../shared/repositories/daily_repository.dart';
import '../../shared/services/refresh.dart';
import '../../shared/services/supabase_providers.dart';

/// What the Daily tab is filtered by. Dates count only as a pair.
class DailyFilters {
  const DailyFilters({this.checkIn, this.checkOut, this.guests, this.cityId});

  final DateTime? checkIn;
  final DateTime? checkOut;
  final int? guests;
  final String? cityId;

  bool get dated => checkIn != null && checkOut != null;
  int get nights => dated ? nightsBetween(checkIn!, checkOut!) : 0;
  bool get any => dated || guests != null || cityId != null;

  DailyFilters copyWith({
    DateTime? checkIn,
    DateTime? checkOut,
    bool clearDates = false,
    int? guests,
    bool clearGuests = false,
    String? cityId,
    bool clearCity = false,
  }) => DailyFilters(
    checkIn: clearDates ? null : (checkIn ?? this.checkIn),
    checkOut: clearDates ? null : (checkOut ?? this.checkOut),
    guests: clearGuests ? null : (guests ?? this.guests),
    cityId: clearCity ? null : (cityId ?? this.cityId),
  );
}

final dailyFiltersProvider = NotifierProvider<DailyFiltersController, DailyFilters>(DailyFiltersController.new);

class DailyFiltersController extends Notifier<DailyFilters> {
  @override
  DailyFilters build() => const DailyFilters();

  void set(DailyFilters f) => state = f;
}

/// Approved daily rentals for the current filters.
final dailySearchProvider = FutureProvider.autoDispose<List<Listing>>((ref) {
  ref.watch(refreshTickProvider);
  final f = ref.watch(dailyFiltersProvider);
  return ref
      .watch(dailyRepositoryProvider)
      .search(checkIn: f.checkIn, checkOut: f.checkOut, guests: f.guests, cityId: f.cityId);
});

/// The nights a listing's calendar greys out, for about a year ahead.
final unavailableDaysProvider = FutureProvider.autoDispose.family<Set<DateTime>, String>((ref, propertyId) {
  final today = dayOnly(DateTime.now());
  return ref.watch(dailyRepositoryProvider).unavailable(propertyId, today, today.add(const Duration(days: 400)));
});

/// The signed-in person's own requests.
final myBookingsProvider = FutureProvider.autoDispose<List<BookingRequest>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(dailyRepositoryProvider).mine();
});

/// Requests for the signed-in owner's listings.
final incomingRequestsProvider = FutureProvider.autoDispose<List<BookingRequest>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(dailyRepositoryProvider).incoming();
});

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(dailyRepositoryProvider).notifications();
});

final unreadNotificationsProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(notificationsProvider).value?.where((n) => n.unread).length ?? 0,
);

/// Requests waiting for this owner's answer.
final pendingRequestsProvider = Provider.autoDispose<int>((ref) {
  final today = DateTime.now();
  return ref
          .watch(incomingRequestsProvider)
          .value
          ?.where((r) => r.status == BookingStatus.pending && !r.expiredOn(today))
          .length ??
      0;
});

/// Keeps the lists above current while signed in: a new request, an answer
/// or an admin's decision arrives as it happens, nothing polls. Watched by
/// the tab shell, so it lives as long as the app does.
final dailyLiveProvider = Provider.autoDispose<void>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  if (uid == null) return;
  final StreamSubscription<void> sub;
  try {
    sub = ref
        .read(dailyRepositoryProvider)
        .changes(uid)
        .listen(
          (_) => ref
            ..invalidate(notificationsProvider)
            ..invalidate(myBookingsProvider)
            ..invalidate(incomingRequestsProvider),
          onError: (Object _) {},
        );
  } on Object {
    return;
  }
  ref.onDispose(sub.cancel);
});
