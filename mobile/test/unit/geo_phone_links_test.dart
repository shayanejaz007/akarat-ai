import 'package:akarat/core/utils/geo.dart';
import 'package:akarat/core/utils/phone.dart';
import 'package:akarat/features/ai_search/domain/portal_links.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:akarat/shared/reference/market_data.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  group('Geo matches lib/geo.js', () {
    test('blur() is deterministic and identical to the website', () {
      for (final p in fixtureList('geo_blur.json')) {
        final out = p['out']! as Map<String, Object?>;
        final got = Geo.blur((p['lat']! as num).toDouble(), (p['lng']! as num).toDouble());
        expect(got.lat, closeTo((out['lat']! as num).toDouble(), 1e-9), reason: 'lat for $p');
        expect(got.lng, closeTo((out['lng']! as num).toDouble(), 1e-9), reason: 'lng for $p');
      }
    });

    test('blur() stays within 300 m', () {
      for (final p in fixtureList('geo_blur.json')) {
        final from = LatLngPoint((p['lat']! as num).toDouble(), (p['lng']! as num).toDouble());
        final to = Geo.blur(from.lat, from.lng);
        expect(Geo.distanceKm(from, to), lessThanOrEqualTo(0.301));
      }
    });

    test('nearestArea() snaps pins the same way', () {
      for (final p in fixtureList('geo_nearest.json')) {
        final out = p['out']! as Map<String, Object?>;
        final got = Geo.nearestArea(LatLngPoint((p['lat']! as num).toDouble(), (p['lng']! as num).toDouble()));
        expect(got.cityId, out['city_id'], reason: '$p');
        expect(got.neighborhoodId, out['neighborhood_id'], reason: '$p');
      }
    });
  });

  group('Phone matches lib/phone.js', () {
    for (final p in fixtureList('phone.json')) {
      test('${p['input']} (${p['country']})', () {
        expect(Phone.toE164(p['input']! as String, p['country']! as String), p['e164']);
        expect(Phone.pretty(p['input']! as String, p['country']! as String), p['pretty']);
      });
    }

    test('WhatsApp targets', () {
      expect(Phone.whatsappTarget('0791234567'), '962791234567');
      expect(Phone.whatsappTarget('+962 79 123 4567'), '962791234567');
      expect(Phone.whatsappTarget('00971501234567'), '971501234567');
      expect(Phone.whatsappTarget('hello'), isNull);
    });

    test('dialable keeps a leading plus and digits only', () {
      expect(Phone.dialable('+962 (79) 123-4567'), '+962791234567');
      expect(Phone.dialable('079 123 4567'), '0791234567');
      expect(Phone.dialable('12'), isNull);
    });
  });

  group('Portal links match lib/providers.js', () {
    for (final p in fixtureList('portal_links.json')) {
      final c = SearchConstraints.fromJson(p['constraints']! as Map<String, Object?>);
      final lang = p['lang']! as String;
      test('${c.toJson()} [$lang]', () {
        expect(PortalLinks.describe(c, lang), p['describe']);
        final expected = (p['searches']! as List<Object?>).cast<Map<String, Object?>>();
        final got = PortalLinks.build(c, lang);
        expect(got.length, expected.length);
        for (var i = 0; i < got.length; i++) {
          expect(got[i].id, expected[i]['id']);
          expect(got[i].name, expected[i]['name']);
          expect(got[i].kind, expected[i]['kind']);
          expect(got[i].url, expected[i]['url']);
          expect(got[i].coverage, expected[i]['coverage']);
          expect(got[i].note, expected[i]['note']);
        }
      });
    }
  });

  test('reference data matches data/market.js', () {
    final m = fixture('market.json')! as Map<String, Object?>;
    final cities = (m['CITIES']! as List<Object?>).cast<Map<String, Object?>>();
    final hoods = (m['NEIGHBORHOODS']! as List<Object?>).cast<Map<String, Object?>>();
    expect(Market.cities.map((c) => c.id).toList(), cities.map((c) => c['id']).toList());
    expect(
      Market.neighborhoods.map((n) => '${n.id}:${n.city}:${n.ar}').toList(),
      hoods.map((n) => '${n['id']}:${n['city']}:${n['ar']}').toList(),
    );
    expect(Market.types.length, (m['TYPES']! as List<Object?>).length);
    expect(Market.amenities.length, (m['AMENITIES']! as List<Object?>).length);
  });
}
