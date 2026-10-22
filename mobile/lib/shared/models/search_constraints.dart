import 'package:flutter/foundation.dart';

/// What a search asks for. The JSON shape is the website's constraints object
/// key for key, because three things read it: the `/api/ai/search` route, the
/// `saved_searches.constraints` jsonb column, and the parity fixtures.
@immutable
class SearchConstraints {
  const SearchConstraints({
    this.deal,
    this.city,
    this.hood,
    this.budgetMax,
    this.budgetMin,
    this.beds,
    this.baths,
    this.type,
    this.areaMin,
    this.amenities = const [],
    this.styles = const [],
    this.internalOnly = false,
  });

  /// 'sale' | 'rent' | null
  final String? deal;
  final String? city;
  final String? hood;
  final int? budgetMax;
  final int? budgetMin;
  final int? beds;
  final int? baths;
  final String? type;
  final int? areaMin;
  final List<String> amenities;
  final List<String> styles;
  final bool internalOnly;

  static const empty = SearchConstraints();

  bool get isEmpty => this == empty;

  /// Number of constraints actually set, as the website's trace counts them.
  int get setCount => [
    deal != null,
    city != null,
    hood != null,
    budgetMax != null,
    budgetMin != null,
    beds != null,
    baths != null,
    type != null,
    areaMin != null,
    amenities.isNotEmpty,
    styles.isNotEmpty,
    internalOnly,
  ].where((x) => x).length;

  static int? _int(Object? v) => switch (v) {
    final int i => i,
    final num n => n.round(),
    _ => null,
  };

  static List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];

  factory SearchConstraints.fromJson(Map<String, Object?> json) => SearchConstraints(
    deal: json['deal'] == 'rent' || json['deal'] == 'sale' ? json['deal']! as String : null,
    city: json['city'] as String?,
    hood: json['hood'] as String?,
    budgetMax: _int(json['budgetMax']),
    budgetMin: _int(json['budgetMin']),
    beds: _int(json['beds']),
    baths: _int(json['baths']),
    type: json['type'] as String?,
    areaMin: _int(json['areaMin']),
    amenities: _strings(json['amenities']),
    styles: _strings(json['styles']),
    internalOnly: json['internalOnly'] == true,
  );

  Map<String, Object?> toJson() => {
    'deal': deal,
    'city': city,
    'hood': hood,
    'budgetMax': budgetMax,
    'budgetMin': budgetMin,
    'beds': beds,
    'baths': baths,
    'type': type,
    'areaMin': areaMin,
    'amenities': amenities,
    'styles': styles,
    'internalOnly': internalOnly,
  };

  /// Every field nullable-settable: pass a value to change it, `clearX: true`
  /// to unset it. Used by the editable chips on the search screen.
  SearchConstraints copyWith({
    String? deal,
    String? city,
    String? hood,
    int? budgetMax,
    int? budgetMin,
    int? beds,
    int? baths,
    String? type,
    int? areaMin,
    List<String>? amenities,
    List<String>? styles,
    bool? internalOnly,
    bool clearDeal = false,
    bool clearCity = false,
    bool clearHood = false,
    bool clearBudgetMax = false,
    bool clearBudgetMin = false,
    bool clearBeds = false,
    bool clearBaths = false,
    bool clearType = false,
    bool clearAreaMin = false,
  }) => SearchConstraints(
    deal: clearDeal ? null : (deal ?? this.deal),
    city: clearCity ? null : (city ?? this.city),
    hood: clearHood ? null : (hood ?? this.hood),
    budgetMax: clearBudgetMax ? null : (budgetMax ?? this.budgetMax),
    budgetMin: clearBudgetMin ? null : (budgetMin ?? this.budgetMin),
    beds: clearBeds ? null : (beds ?? this.beds),
    baths: clearBaths ? null : (baths ?? this.baths),
    type: clearType ? null : (type ?? this.type),
    areaMin: clearAreaMin ? null : (areaMin ?? this.areaMin),
    amenities: amenities ?? this.amenities,
    styles: styles ?? this.styles,
    internalOnly: internalOnly ?? this.internalOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchConstraints &&
      other.deal == deal &&
      other.city == city &&
      other.hood == hood &&
      other.budgetMax == budgetMax &&
      other.budgetMin == budgetMin &&
      other.beds == beds &&
      other.baths == baths &&
      other.type == type &&
      other.areaMin == areaMin &&
      listEquals(other.amenities, amenities) &&
      listEquals(other.styles, styles) &&
      other.internalOnly == internalOnly;

  @override
  int get hashCode => Object.hash(
    deal,
    city,
    hood,
    budgetMax,
    budgetMin,
    beds,
    baths,
    type,
    areaMin,
    Object.hashAll(amenities),
    Object.hashAll(styles),
    internalOnly,
  );

  @override
  String toString() => 'SearchConstraints(${toJson()})';
}
