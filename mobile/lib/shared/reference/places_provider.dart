import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_providers.dart';
import 'places.dart';

/// The places in use: what the app ships with, with an admin's changes from
/// the database laid over it, and whether the database has every place yet.
class PlacesState {
  const PlacesState(this.places, {required this.inDatabase});

  final Places places;

  /// False until supabase/migrations/0023_locations.sql has run: the
  /// database then knows only the hand-checked core, and a listing in any
  /// other town would be refused. Pickers keep to the core until it is true.
  final bool inDatabase;

  /// A place that can be chosen now.
  bool choosable(Place p) => inDatabase || p.kind == PlaceKind.gov || p.core;
}

/// Starts as the bundled list and becomes the edited one once the database
/// answers; offline, the bundled list is all there is, and that is enough.
final placesProvider = FutureProvider<PlacesState>((ref) async {
  final db = ref.watch(supabaseClientProvider);
  const pick = 'id,name_en,name_ar,lat,lng,aliases,active';
  try {
    final rows = await Future.wait([
      db.from('governorates').select(pick).eq('edited', true).limit(500),
      db.from('cities').select('$pick,governorate_id').eq('edited', true).limit(3000),
      db.from('neighborhoods').select('$pick,city_id').eq('edited', true).limit(3000),
    ]);
    List<Map<String, Object?>> m(List<dynamic> r) => [for (final x in r) Map<String, Object?>.from(x as Map)];
    final edits = {'governorates': m(rows[0]), 'cities': m(rows[1]), 'neighborhoods': m(rows[2])};
    final any = edits.values.any((v) => v.isNotEmpty);
    return PlacesState(any ? Places.withEdits(edits) : Places.bundled, inDatabase: true);
  } on Object {
    // No such columns (0023 not run), or no connection.
    return PlacesState(Places.bundled, inDatabase: false);
  }
});

/// What to use right now: the edited list once it has loaded, the bundled
/// one until then (never a spinner for a place name).
final placesNowProvider = Provider<PlacesState>((ref) {
  return ref.watch(placesProvider).value ?? PlacesState(Places.bundled, inDatabase: false);
});
