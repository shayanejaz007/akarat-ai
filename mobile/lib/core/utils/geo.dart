import 'dart:math' as math;

import '../../shared/reference/market_data.dart';

/// Location privacy and snapping, ported from the website's lib/geo.js.
///
/// The exact pin an owner places is written to `property_locations`, which
/// only that owner can read (migration 0010). What goes on the public
/// `properties` row is either that pin (when the owner chose "exact") or the
/// displaced point [blur] returns. Both clients must displace identically, or
/// an edit made in one would walk the published point away from where the
/// other put it. test/geo_test.dart checks this against the website's output.
class Geo {
  const Geo._();

  static const double blurRadiusMetres = 300;
  static const LatLngPoint jordanCenter = LatLngPoint(31.963, 35.93);

  /// A point up to ~300 m from the real one, stable for a given input.
  ///
  /// Deterministic: seeded from the coordinates themselves, so the circle lands
  /// in the same place on every save. A fresh random offset per save would let
  /// anyone average many versions back to the truth. And an offset rather than
  /// a rounding, because rounding snaps to a grid that gives the cell away.
  static LatLngPoint blur(double lat, double lng) {
    final h = _seed(lat, lng);
    final angle = ((h & 0xffff) / 0xffff) * 2 * math.pi;
    final radius = blurRadiusMetres * math.sqrt(((h >> 16) & 0xffff) / 0xffff);
    final dLat = (radius * math.cos(angle)) / 111320;
    final dLng = (radius * math.sin(angle)) / (111320 * math.cos((lat * math.pi) / 180));
    return LatLngPoint(double.parse((lat + dLat).toStringAsFixed(6)), double.parse((lng + dLng).toStringAsFixed(6)));
  }

  /// FNV-1a over the fixed-precision coordinates, in unsigned 32-bit
  /// arithmetic — the same bits JavaScript's Math.imul(...) >>> 0 produces.
  static int _seed(double lat, double lng) {
    final str = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    var h = 0x811c9dc5;
    for (final unit in str.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  static double distanceKm(LatLngPoint a, LatLngPoint b) {
    double rad(double d) => (d * math.pi) / 180;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final s =
        math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * 6371 * math.asin(math.sqrt(s));
  }

  /// The closest known city and area to a dropped pin.
  ///
  /// city_id and neighborhood_id are foreign keys that search, deduplication
  /// and the Arabic place names all read, so a pin never replaces them; it is
  /// snapped back onto the taxonomy. An area is accepted only within 6 km of
  /// its centre — past that, guessing would put the listing on a search page
  /// it does not belong on. A city is always returned.
  static ({String? cityId, String? neighborhoodId}) nearestArea(LatLngPoint at) {
    Neighborhood? hood;
    var hoodKm = double.infinity;
    for (final n in Market.neighborhoods) {
      final km = distanceKm(at, LatLngPoint(n.lat, n.lng));
      if (km < hoodKm) {
        hoodKm = km;
        hood = n;
      }
    }
    if (hoodKm > 6) hood = null;

    City? city;
    if (hood != null) {
      city = Market.city(hood.city);
    } else {
      var cityKm = double.infinity;
      for (final c in Market.cities) {
        final km = distanceKm(at, LatLngPoint(c.lat, c.lng));
        if (km < cityKm) {
          cityKm = km;
          city = c;
        }
      }
    }
    return (cityId: city?.id, neighborhoodId: hood?.id);
  }
}

/// A coordinate pair without pulling the maps plugin into pure logic.
class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is LatLngPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLngPoint($lat, $lng)';
}
