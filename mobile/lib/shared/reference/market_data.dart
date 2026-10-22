/// Canonical Jordanian reference data: cities, areas, property types and
/// amenities. Generated from the website's data/market.js, which also seeds
/// the `cities` and `neighborhoods` tables (migration 0009), so an id chosen
/// here is always a valid foreign key on `properties`.
library;

part 'market_data.g.dart';

/// Something with an English and an Arabic name.
abstract class Bilingual {
  const Bilingual();
  String get id;
  String get en;
  String get ar;

  /// The name in [lang], falling back to English.
  String label(String lang) => lang == 'ar' ? ar : en;
}

class City extends Bilingual {
  const City({
    required this.id,
    required this.en,
    required this.ar,
    required this.lat,
    required this.lng,
    this.alt = const [],
  });

  @override
  final String id;
  @override
  final String en;
  @override
  final String ar;
  final double lat;
  final double lng;

  /// Alternative spellings people type, used by the query parser.
  final List<String> alt;
}

class Neighborhood extends Bilingual {
  const Neighborhood({
    required this.id,
    required this.city,
    required this.en,
    required this.ar,
    required this.lat,
    required this.lng,
    this.alt = const [],
  });

  @override
  final String id;

  /// The parent city id.
  final String city;
  @override
  final String en;
  @override
  final String ar;
  final double lat;
  final double lng;
  final List<String> alt;
}

class Amenity extends Bilingual {
  const Amenity({required this.id, required this.en, required this.ar});
  @override
  final String id;
  @override
  final String en;
  @override
  final String ar;
}

class PropertyType extends Bilingual {
  const PropertyType({required this.id, required this.en, required this.ar});
  @override
  final String id;
  @override
  final String en;
  @override
  final String ar;
}

/// Lookup helpers over the generated tables.
class Market {
  const Market._();

  static const List<City> cities = _cities;
  static const List<Neighborhood> neighborhoods = _neighborhoods;
  static const List<Amenity> amenities = _amenities;
  static const List<PropertyType> types = _types;

  /// Confidence in a SOURCE kind, not in any one property. Feeds ranking.
  static const Map<String, double> sourceConfidence = _sourceConfidence;

  static City? city(String? id) => _find(cities, id);
  static Neighborhood? neighborhood(String? id) => _find(neighborhoods, id);
  static PropertyType? type(String? id) => _find(types, id);
  static Amenity? amenity(String? id) => _find(amenities, id);

  static List<Neighborhood> neighborhoodsOf(String? cityId) =>
      cityId == null ? const [] : neighborhoods.where((n) => n.city == cityId).toList();

  /// "Abdoun · Amman", or just the city, or empty when neither is known.
  static String placeLabel(String? cityId, String? hoodId, String lang) {
    final parts = <String>[
      if (neighborhood(hoodId) case final n?) n.label(lang),
      if (city(cityId) case final c?) c.label(lang),
    ];
    return parts.join(' · ');
  }

  static T? _find<T extends Bilingual>(List<T> list, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }
}
