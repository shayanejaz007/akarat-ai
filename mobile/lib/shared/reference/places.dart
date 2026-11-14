/// Jordan's places for pickers, filters and place names: the 12
/// governorates, then cities, towns and villages, then neighbourhoods
/// (the website's data/locations.js, generated into places_data.g.dart).
///
/// The search is a port of the website's lib/places.js and must answer the
/// same way: test/unit/places_test.dart checks it against what the website
/// returns (test/fixtures/places_parity.json). It forgives what people
/// type: Arabic with or without the article, hamza or taa marbuta; English
/// in any of the usual spellings ("Sweifieh", "Swaifieh", "Suwayfiyah");
/// and any level, so choosing a neighbourhood fills in its city and
/// governorate.
///
/// [Market] (market_data.dart) keeps the hand-checked core that the query
/// parser reads; this is everything else.
library;

import 'dart:math' as math;

part 'places_data.g.dart';

enum PlaceKind { gov, city, hood }

class Place {
  const Place(
    this.kind,
    this.id,
    this.parent,
    this.en,
    this.ar,
    this.lat,
    this.lng, [
    this.alt = const [],
    this.core = false,
    this.active = true,
  ]);

  final PlaceKind kind;
  final String id;

  /// A city's governorate, a neighbourhood's city; null for a governorate.
  final String? parent;
  final String en;
  final String ar;
  final double lat;
  final double lng;

  /// Other spellings people type.
  final List<String> alt;

  /// One of the hand-checked places (data/market.js): ranked first.
  final bool core;

  /// Switched off by an admin: hidden from pickers, still named on old listings.
  final bool active;

  String label(String lang) => lang == 'ar' ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en);
}

/// A place chosen at any level. Empty strings are read as null.
class PlaceSel {
  const PlaceSel({this.governorateId, this.cityId, this.neighborhoodId});

  final String? governorateId;
  final String? cityId;
  final String? neighborhoodId;

  static String? _v(String? s) => s == null || s.isEmpty ? null : s;
  String? get gov => _v(governorateId);
  String? get city => _v(cityId);
  String? get hood => _v(neighborhoodId);

  bool get isEmpty => gov == null && city == null && hood == null;

  @override
  bool operator ==(Object other) => other is PlaceSel && other.gov == gov && other.city == city && other.hood == hood;

  @override
  int get hashCode => Object.hash(gov, city, hood);

  @override
  String toString() => 'PlaceSel($gov, $city, $hood)';
}

class PlaceHit {
  const PlaceHit({
    required this.kind,
    required this.id,
    required this.label,
    required this.path,
    required this.score,
    required this.sel,
  });
  final PlaceKind kind;
  final String id;
  final String label;

  /// Where it is: "Amman · Amman governorate".
  final String path;
  final int score;
  final PlaceSel sel;
}

/* ── folding ─────────────────────────────────────────────────────────── */

final _arabic = RegExp('[؀-ۿ]');
bool isArabicText(String s) => _arabic.hasMatch(s);

final _marks = RegExp('[ً-ٰـ]');
final _notArabic = RegExp('[^ء-ي\\s]');
final _arWords = RegExp(r'(^|\s)(حي|منطقة|ضاحية)(?=\s)');
final _arArticle = RegExp(r'(^|\s)(و?ب?ال)(?=\S{2})');
final _space = RegExp(r'\s+');

/// Arabic folded for comparison: no marks, one alef, no article, no spaces.
String foldAr(String s) => s
    .replaceAll(_marks, '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll('ء', '')
    .replaceAll(_notArabic, ' ')
    .replaceAll(_arWords, ' ')
    .replaceAllMapped(_arArticle, (m) => m[1]!)
    .replaceAll(_space, '');

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ç': 'c',
  'ć': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'ḍ': 'd',
  'ḑ': 'd',
  'ḏ': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ǧ': 'g',
  'ĥ': 'h',
  'ħ': 'h',
  'ḥ': 'h',
  'ḩ': 'h',
  'ḫ': 'h',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ĩ': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ı': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ŀ': 'l',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'ŕ': 'r',
  'ŗ': 'r',
  'ř': 'r',
  'ś': 's',
  'ŝ': 's',
  'ş': 's',
  'š': 's',
  'ṣ': 's',
  'ţ': 't',
  'ť': 't',
  'ŧ': 't',
  'ṭ': 't',
  'ṯ': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ŵ': 'w',
  'ý': 'y',
  'ÿ': 'y',
  'ŷ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'ẓ': 'z',
  'ẕ': 'z',
};
final _combining = RegExp('[̀-ͯ]');
final _quotes = RegExp('[‘’`\'ʿʾ]');
final _enArticle = RegExp(r'(^|[\s-])(al|el|ar|as|ash|at|ad|adh|az|an|ath)[\s-]+(?=\S)');
final _enWords = RegExp(r'^(hayy|hay|mintaqat)\s+');
final _notWord = RegExp('[^a-z0-9]');

/// English folded for comparison: lower case, no accents, articles or punctuation.
String foldEn(String s) {
  final lower = s.toLowerCase().replaceAll(_combining, '');
  final plain = StringBuffer();
  for (final ch in lower.split('')) {
    plain.write(_accents[ch] ?? ch);
  }
  return plain
      .toString()
      .replaceAll(_quotes, '')
      .replaceAllMapped(_enArticle, (m) => m[1]!)
      .replaceAll(_enWords, '')
      .replaceAll(_notWord, '');
}

final _repeat = RegExp(r'(.)\1+');
final _vowels = RegExp('[aeiouyw]');

/// The consonants of a folded English name: what survives every transliteration.
String skeleton(String folded) =>
    folded.replaceAllMapped(_repeat, (m) => m[1]!).replaceAll(_vowels, '').replaceAllMapped(_repeat, (m) => m[1]!);

class _Terms {
  _Terms(this.en, this.sk, this.ar);
  final List<String> en;
  final List<String> sk;
  final List<String> ar;
}

_Terms _termsOf(Place x) {
  final en = <String>{};
  final ar = <String>{};
  for (final t in [x.en, x.ar, ...x.alt]) {
    if (t.isEmpty) continue;
    if (isArabicText(t)) {
      final f = foldAr(t);
      if (f.isNotEmpty) ar.add(f);
    } else {
      final f = foldEn(t);
      if (f.isNotEmpty) en.add(f);
    }
  }
  // Each skeleton keeps the name's first letter: consonants alone match too much.
  final sk = {for (final t in en) t[0] + skeleton(t)}.where((s) => s.length >= 3).toList();
  return _Terms(en.toList(), sk, ar.toList());
}

class _Entry {
  _Entry(this.kind, this.x, this.t, this.weight);
  final PlaceKind kind;
  final Place x;
  final _Terms t;
  final int weight;
}

final _govWord = RegExp(
  r'(^|\s)(governorate|governate|gov|muhafazat|muhafazah|محافظة|محافظه)(?=\s|$)',
  caseSensitive: false,
);

/// The places, with lookups and search.
class Places {
  Places._(List<Place> govs, List<Place> cities, List<Place> hoods)
    : governorates = govs.where((g) => g.active).toList(),
      cities = cities.where((c) => c.active).toList(),
      hoods = hoods.where((h) => h.active).toList(),
      _anyGov = {for (final g in govs) g.id: g},
      _anyCity = {for (final c in cities) c.id: c},
      _anyHood = {for (final h in hoods) h.id: h} {
    _govById.addAll({for (final g in governorates) g.id: g});
    _cityById.addAll({for (final c in this.cities) c.id: c});
    _hoodById.addAll({for (final h in this.hoods) h.id: h});
  }

  /// The places the app ships with.
  static final Places bundled = Places._(_governorates, _cities, _neighborhoods);

  /// [bundled] with an admin's changes laid over it: rows from the
  /// database's governorates, cities and neighborhoods tables marked edited,
  /// in the tables' own column names. A row switched off hides the place;
  /// an unknown id adds one.
  factory Places.withEdits(Map<String, List<Map<String, Object?>>> rows) {
    List<Place> lay(List<Place> base, List<Map<String, Object?>>? edits, PlaceKind kind, String? parentKey) {
      final out = [...base];
      for (final r in edits ?? const <Map<String, Object?>>[]) {
        final id = '${r['id'] ?? ''}';
        if (id.isEmpty) continue;
        final i = out.indexWhere((p) => p.id == id);
        final old = i >= 0 ? out[i] : null;
        double? d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
        final aliases = r['aliases'];
        final next = Place(
          kind,
          id,
          parentKey == null ? null : ('${r[parentKey] ?? ''}'.isEmpty ? old?.parent : '${r[parentKey]}'),
          '${r['name_en'] ?? old?.en ?? ''}',
          '${r['name_ar'] ?? old?.ar ?? ''}',
          d(r['lat']) ?? old?.lat ?? 0,
          d(r['lng']) ?? old?.lng ?? 0,
          aliases is List ? aliases.map((a) => '$a').toList() : (old?.alt ?? const []),
          old?.core ?? false,
          r['active'] != false,
        );
        if (i >= 0) {
          out[i] = next;
        } else {
          out.add(next);
        }
      }
      return out;
    }

    return Places._(
      lay(_governorates, rows['governorates'], PlaceKind.gov, null),
      lay(_cities, rows['cities'], PlaceKind.city, 'governorate_id'),
      lay(_neighborhoods, rows['neighborhoods'], PlaceKind.hood, 'city_id'),
    );
  }

  /// The places that can be chosen.
  final List<Place> governorates;
  final List<Place> cities;
  final List<Place> hoods;
  final _govById = <String, Place>{};
  final _cityById = <String, Place>{};
  final _hoodById = <String, Place>{};
  // Switched-off places too, for naming.
  final Map<String, Place> _anyGov;
  final Map<String, Place> _anyCity;
  final Map<String, Place> _anyHood;
  List<_Entry>? _index;

  Place? gov(String? id) => id == null ? null : _govById[id];
  Place? city(String? id) => id == null ? null : _cityById[id];
  Place? hood(String? id) => id == null ? null : _hoodById[id];
  List<Place> citiesOf(String? govId) => govId == null ? const [] : cities.where((c) => c.parent == govId).toList();
  List<Place> hoodsOf(String? cityId) => cityId == null ? const [] : hoods.where((h) => h.parent == cityId).toList();
  String? govOfCity(String? cityId) => cityId == null ? null : _anyCity[cityId]?.parent;

  static String _name(Place? x, String lang) => x == null ? '' : x.label(lang);

  /// "Abdoun · Amman", the city alone, or empty. Names switched-off places too.
  String placeLabel(String? cityId, String? hoodId, String lang) => [
    _name(hoodId == null ? null : _anyHood[hoodId], lang),
    _name(cityId == null ? null : _anyCity[cityId], lang),
  ].where((s) => s.isNotEmpty).join(' · ');

  /// "Amman governorate" / "محافظة عمّان".
  String govLabel(String? id, String lang) {
    final g = id == null ? null : _anyGov[id];
    if (g == null) return '';
    return lang == 'ar' ? 'محافظة ${g.ar}' : '${g.en} governorate';
  }

  /// A choice in words, at whatever level it was made.
  String selLabel(PlaceSel? sel, String lang) {
    if (sel == null || sel.isEmpty) return '';
    if (sel.city != null || sel.hood != null) return placeLabel(sel.city, sel.hood, lang);
    return govLabel(sel.gov, lang);
  }

  /// Every level of a place chosen at one of them.
  PlaceSel? selection(PlaceKind kind, String id) {
    switch (kind) {
      case PlaceKind.hood:
        final h = _hoodById[id];
        return h == null ? null : PlaceSel(governorateId: govOfCity(h.parent), cityId: h.parent, neighborhoodId: h.id);
      case PlaceKind.city:
        final c = _cityById[id];
        return c == null ? null : PlaceSel(governorateId: c.parent, cityId: c.id);
      case PlaceKind.gov:
        final g = _govById[id];
        return g == null ? null : PlaceSel(governorateId: g.id);
    }
  }

  /// A listing in [cityId] / [hoodId] matches a filter on [sel] (any level, or none).
  bool inArea(String? cityId, String? hoodId, PlaceSel? sel) {
    if (sel == null || sel.isEmpty) return true;
    if (sel.hood != null) return hoodId == sel.hood;
    if (sel.city != null) return cityId == sel.city;
    return govOfCity(cityId) == sel.gov;
  }

  /// Where a map should look for a choice, and how close.
  ({double lat, double lng, double zoom})? centre(PlaceSel? sel) {
    if (sel == null) return null;
    final h = hood(sel.hood);
    if (h != null && h.lat != 0) return (lat: h.lat, lng: h.lng, zoom: 15);
    final c = city(sel.city);
    if (c != null && c.lat != 0) return (lat: c.lat, lng: c.lng, zoom: 13);
    final g = gov(sel.gov);
    if (g != null && g.lat != 0) return (lat: g.lat, lng: g.lng, zoom: 10);
    return null;
  }

  /// The town nearest a point, and the neighbourhood when one is within 6 km.
  PlaceSel nearest(double lat, double lng) {
    Place? near(List<Place> list, double? capKm) {
      Place? best;
      var bestKm = double.infinity;
      for (final p in list) {
        if (p.lat == 0 && p.lng == 0) continue;
        final km = _distanceKm(lat, lng, p.lat, p.lng);
        if (km < bestKm) {
          bestKm = km;
          best = p;
        }
      }
      return capKm != null && bestKm > capKm ? null : best;
    }

    final h = near(hoods, 6);
    final c = h != null ? city(h.parent) : near(cities, null);
    return PlaceSel(governorateId: c?.parent, cityId: c?.id, neighborhoodId: h?.id);
  }

  String _pathOf(PlaceKind kind, Place x, String lang) {
    final ar = lang == 'ar';
    String govWord(Place? g) => g == null ? '' : (ar ? 'محافظة ${g.ar}' : '${g.en} governorate');
    switch (kind) {
      case PlaceKind.hood:
        final c = _cityById[x.parent];
        return [_name(c, lang), govWord(_govById[c?.parent])].where((s) => s.isNotEmpty).join(' · ');
      case PlaceKind.city:
        return govWord(_govById[x.parent]);
      case PlaceKind.gov:
        return ar ? 'المحافظة كاملة' : 'The whole governorate';
    }
  }

  List<_Entry> _build() => _index ??= [
    // A city outranks the governorate named after it: "Irbid" is usually the city.
    for (final x in governorates) _Entry(PlaceKind.gov, x, _termsOf(x), 8),
    for (final x in cities) _Entry(PlaceKind.city, x, _termsOf(x), x.core ? 10 : 4),
    for (final x in hoods) _Entry(PlaceKind.hood, x, _termsOf(x), x.core ? 9 : 2),
  ];

  /// Places matching what was typed, best first. [kinds] limits the levels;
  /// [gov] and [city] limit the area searched.
  List<PlaceHit> search(
    String query, {
    String lang = 'en',
    Set<PlaceKind>? kinds,
    String? gov,
    String? city,
    int limit = 12,
  }) {
    var levels = kinds == null || kinds.isEmpty ? PlaceKind.values.toSet() : kinds;
    var raw = query.trim();
    // "Irbid governorate", "محافظة إربد": the word asks for the governorate.
    if (_govWord.hasMatch(raw) && levels.contains(PlaceKind.gov)) {
      raw = raw.replaceAll(_govWord, ' ').trim();
      levels = {PlaceKind.gov};
    }
    if (raw.isEmpty) return const [];
    final ar = isArabicText(raw);
    final q = ar ? foldAr(raw) : foldEn(raw);
    if (q.isEmpty) return const [];
    final qs = ar ? '' : q[0] + skeleton(q);
    final hits = <(_Entry, int, int)>[];
    var order = 0;
    for (final e in _build()) {
      order++;
      if (!levels.contains(e.kind)) continue;
      final egov = switch (e.kind) {
        PlaceKind.gov => e.x.id,
        PlaceKind.city => e.x.parent,
        PlaceKind.hood => govOfCity(e.x.parent),
      };
      if (gov != null && egov != gov) continue;
      if (city != null &&
          (e.kind == PlaceKind.gov || (e.kind == PlaceKind.city ? e.x.id != city : e.x.parent != city))) {
        continue;
      }
      var score = 0;
      for (final t in ar ? e.t.ar : e.t.en) {
        var s = 0;
        if (t == q) {
          s = 100;
        } else if (t.startsWith(q)) {
          s = 80 - math.min(20, t.length - q.length);
        } else if (q.length >= 3 && t.contains(q)) {
          s = 40;
        }
        if (s > score) score = s;
      }
      // "Swaifieh" for "Sweifieh": the consonants agree.
      if (!ar && score < 60 && qs.length >= 4) {
        for (final t in e.t.sk) {
          if (t == qs) {
            score = math.max(score, 70);
            break;
          }
          if (t.startsWith(qs)) score = math.max(score, 55);
        }
      }
      if (score == 0) continue;
      hits.add((e, score + e.weight, order));
    }
    // Stable, as the website's sort is: ties keep the list's order.
    hits.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      final byLength = _name(a.$1.x, lang).length.compareTo(_name(b.$1.x, lang).length);
      return byLength != 0 ? byLength : a.$3.compareTo(b.$3);
    });
    return [
      for (final (e, score, _) in hits.take(limit))
        PlaceHit(
          kind: e.kind,
          id: e.x.id,
          // A governorate says so, so "Aqaba" the city and "Aqaba governorate" read apart.
          label: e.kind == PlaceKind.gov
              ? (lang == 'ar' ? 'محافظة ${e.x.ar}' : '${e.x.en} governorate')
              : _name(e.x, lang),
          path: _pathOf(e.kind, e.x, lang),
          score: score,
          sel: selection(e.kind, e.x.id) ?? const PlaceSel(),
        ),
    ];
  }
}

double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final s =
      math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(s));
}
