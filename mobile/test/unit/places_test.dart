// The app's place search (lib/shared/reference/places.dart) against the
// website's (lib/places.js): test/fixtures/places_parity.json holds what the
// website answers, written by tool/gen_places.mjs. The two must agree, so a
// place found on the website is found in the app, in the same order.
import 'dart:convert';
import 'dart:io';

import 'package:akarat/shared/reference/market_data.dart';
import 'package:akarat/shared/reference/places.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = jsonDecode(File('test/fixtures/places_parity.json').readAsStringSync()) as Map<String, dynamic>;
  final places = Places.bundled;

  test('every place from data/locations.js, and nothing switched off', () {
    final counts = fixture['counts'] as Map<String, dynamic>;
    expect(places.governorates, hasLength(counts['governorates']));
    expect(places.cities, hasLength(counts['cities']));
    expect(places.hoods, hasLength(counts['hoods']));
    expect(places.governorates, hasLength(12));
  });

  test('search answers exactly as the website does, in both languages', () {
    for (final raw in fixture['search'] as List) {
      final c = raw as Map<String, dynamic>;
      final hits = places.search(c['q'] as String, lang: c['lang'] as String, limit: 5);
      final want = (c['hits'] as List).cast<Map<String, dynamic>>();
      expect(
        [for (final h in hits) '${h.kind.name}:${h.id}:${h.label}:${h.sel.gov}:${h.sel.city}:${h.sel.hood}'],
        [for (final h in want) '${h['kind']}:${h['id']}:${h['label']}:${h['gov']}:${h['city']}:${h['hood']}'],
        reason: 'query "${c['q']}"',
      );
    }
  });

  test('place labels as the website writes them', () {
    for (final raw in fixture['labels'] as List) {
      final c = raw as Map<String, dynamic>;
      expect(places.placeLabel(c['city'] as String?, c['hood'] as String?, c['lang'] as String), c['label']);
    }
  });

  test('every hand-checked place is still there with the same id and city', () {
    for (final c in Market.cities) {
      expect(places.city(c.id), isNotNull, reason: c.id);
    }
    for (final n in Market.neighborhoods) {
      expect(places.hood(n.id)?.parent, n.city, reason: n.id);
    }
  });

  test('a filter at any level', () {
    const g = PlaceSel(governorateId: 'amman');
    expect(places.inArea('amman', 'abdoun', g), isTrue);
    expect(places.inArea('irbid', null, g), isFalse);
    expect(
      places.inArea(
        'amman',
        'abdoun',
        const PlaceSel(governorateId: 'amman', cityId: 'amman', neighborhoodId: 'khalda'),
      ),
      isFalse,
    );
    expect(places.inArea('ramtha', null, null), isTrue);
  });

  test("an admin's changes: a rename, a new area, a place switched off", () {
    final edited = Places.withEdits({
      'cities': [
        {
          'id': 'sahab',
          'governorate_id': 'amman',
          'name_en': 'Sahab City',
          'name_ar': 'مدينة سحاب',
          'aliases': ['sahhab'],
          'active': true,
        },
      ],
      'neighborhoods': [
        {
          'id': 'new-hood',
          'city_id': 'amman',
          'name_en': 'Green Hills',
          'name_ar': 'التلال الخضراء',
          'aliases': <String>[],
          'active': true,
        },
        {'id': 'dabouq', 'city_id': 'amman', 'name_en': 'Dabouq', 'name_ar': 'دابوق', 'active': false},
      ],
    });
    expect(edited.city('sahab')!.en, 'Sahab City');
    expect(edited.search('sahhab').first.id, 'sahab');
    expect(edited.search('green hills').first.id, 'new-hood');
    expect(edited.search('التلال الخضراء', lang: 'ar').first.sel.city, 'amman');
    expect(edited.hood('dabouq'), isNull, reason: 'switched off: not offered');
    expect(edited.placeLabel('amman', 'dabouq', 'en'), 'Dabouq · Amman', reason: 'still named on old listings');
  });

  test('a pin names its town, and a neighbourhood only when one is close', () {
    final abdoun = places.hood('abdoun')!;
    final near = places.nearest(abdoun.lat, abdoun.lng);
    expect([near.gov, near.city, near.hood], ['amman', 'amman', 'abdoun']);
    // The middle of the eastern desert: a town, but no neighbourhood.
    final far = places.nearest(31.6, 37.9);
    expect(far.city, isNotNull);
    expect(far.hood, isNull);
  });

  test('a choice in words, at any level', () {
    expect(places.selLabel(const PlaceSel(governorateId: 'irbid'), 'en'), 'Irbid governorate');
    expect(places.selLabel(const PlaceSel(governorateId: 'irbid'), 'ar'), 'محافظة إربد');
    expect(
      places.selLabel(const PlaceSel(governorateId: 'amman', cityId: 'amman', neighborhoodId: 'abdoun'), 'en'),
      'Abdoun · Amman',
    );
    expect(places.selLabel(null, 'en'), '');
  });
}
