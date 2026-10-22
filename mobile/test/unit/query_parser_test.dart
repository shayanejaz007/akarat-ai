import 'package:akarat/features/ai_search/domain/query_parser.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  group('QueryParser matches the website (lib/aisearch.js)', () {
    for (final entry in fixtureList('parse_query.json')) {
      final input = entry['input']! as String;
      final previousJson = entry['previous'] as Map<String, Object?>?;
      final expected = entry['result']! as Map<String, Object?>;

      test(previousJson == null ? input : '$input  (refining)', () {
        final previous = previousJson == null ? null : SearchConstraints.fromJson(previousJson);
        final got = QueryParser.parse(input, previous);
        expect(got.lang, expected['lang']);
        expect(got.text, expected['text']);

        if (!_readsMoreThanWebsite.containsKey(input)) {
          expect(got.constraints.toJson(), expected['constraints'], reason: 'constraints for "$input"');
          expect(got.changed, expected['changed']);
          expect(got.missing, expected['missing']);
          return;
        }
        // The app's extensions understand more here: everything the website
        // read must still be read the same; only what it missed may differ.
        final want = expected['constraints']! as Map<String, Object?>;
        final have = got.constraints.toJson();
        for (final MapEntry(:key, :value) in want.entries) {
          final empty = value == null || value == false || (value is List && value.isEmpty);
          if (!empty) expect(have[key], value, reason: '$key for "$input"');
        }
        for (final MapEntry(:key, :value) in _readsMoreThanWebsite[input]!.entries) {
          expect(have[key], value, reason: 'extension: $key for "$input"');
        }
        expect(got.changed, containsAll(expected['changed']! as List));
      });
    }
  });

  group('QueryParser reads how Jordanians ask (app extensions)', () {
    test('the English example from the Phase 2 brief', () {
      final c = QueryParser.parse(
        'Find me a modern three-bedroom apartment in Abdoun, Amman, under 150,000 JOD, '
        'preferably with parking and a balcony.',
      ).constraints;
      expect(c.type, 'apartment');
      expect(c.hood, 'abdoun');
      expect(c.city, 'amman');
      expect(c.beds, 3);
      expect(c.budgetMax, 150000);
      expect(c.amenities, containsAll(['parking', 'balcony']));
      expect(c.styles, contains('modern'));
    });

    test('the Jordanian Arabic example from the brief', () {
      final c = QueryParser.parse(
        'بدي شقة بعبدون، ثلاث غرف نوم، وسعرها ما يتجاوز ١٥٠ ألف دينار، ويكون فيها كراج وبلكونة.',
      ).constraints;
      expect(c.type, 'apartment');
      expect(c.hood, 'abdoun');
      expect(c.beds, 3);
      expect(c.budgetMax, 150000);
      expect(c.amenities, containsAll(['parking', 'balcony']));
    });

    test('the spoken land example: about 500 m, budget 80 thousand', () {
      final c = QueryParser.parse('بدي أرض في عمان، حوالي ٥٠٠ متر، وميزانيتي ٨٠ ألف دينار.').constraints;
      expect(c.type, 'land');
      expect(c.city, 'amman');
      expect(c.areaMin, 450, reason: 'about 500 m: a little under counts');
      expect(c.budgetMax, 80000);
    });

    test('spoken amounts, in both languages', () {
      expect(QueryParser.parse('شقة بحدود مية وخمسين ألف دينار').constraints.budgetMax, 150000);
      expect(QueryParser.parse('فيلا ميزانيتي ربع مليون').constraints.budgetMax, 250000);
      expect(QueryParser.parse('بيت تحت مليون ونص').constraints.budgetMax, 1500000);
      expect(QueryParser.parse('apartment under eighty thousand JOD').constraints.budgetMax, 80000);
      expect(QueryParser.parse('villa up to a hundred and fifty thousand').constraints.budgetMax, 150000);
      expect(QueryParser.parse('land under two and a half million').constraints.budgetMax, 2500000);
      expect(QueryParser.parse('ارض خمسمية متر في مادبا').constraints.areaMin, 500);
    });

    test('Jordanian words for renting, features and budgets', () {
      final c = QueryParser.parse('بدي شقة اجار بالصويفية فيها جنينة وشوفاج، ما بدي مفروشة').constraints;
      expect(c.deal, 'rent');
      expect(c.hood, 'sweifieh');
      expect(c.amenities, containsAll(['garden', 'heating']));
      expect(c.amenities, isNot(contains('furnished')));
    });

    test('unfurnished is not furnished', () {
      expect(QueryParser.parse('unfurnished flat in Khalda').constraints.amenities, isNot(contains('furnished')));
      expect(QueryParser.parse('شقة غير مفروشة في خلدا').constraints.amenities, isNot(contains('furnished')));
    });

    test('mixed Arabic and English in one sentence', () {
      final c = QueryParser.parse('بدي apartment في Jbeiha with 3 bedrooms تحت 90 ألف').constraints;
      expect(c.type, 'apartment');
      expect(c.hood, 'jubaiha');
      expect(c.beds, 3);
      expect(c.budgetMax, 90000);
    });

    test('a lone word that is also a number is left alone', () {
      // "مية" is also "water"; "three bedrooms" is the parser's own rule.
      expect(QueryParser.parse('شقة فيها مية وكهربا').constraints.budgetMax, isNull);
      expect(QueryParser.parse('three bedroom villa').constraints.beds, 3);
    });
  });

  group('QueryParser examples from the brief', () {
    test('Jordanian Arabic: two bedrooms in Amman under 80 thousand', () {
      final c = QueryParser.parse('بدي شقة بعمان غرفتين وبسعر أقل من ٨٠ ألف دينار').constraints;
      expect(c.city, 'amman');
      expect(c.type, 'apartment');
      expect(c.beds, 2);
      expect(c.budgetMax, 80000);
    });

    test('an area is not a budget', () {
      final c = QueryParser.parse('max 300 sqm office in Shmeisani').constraints;
      expect(c.budgetMax, isNull);
      expect(c.hood, 'shmeisani');
      expect(c.type, 'office');
    });

    test('warehouse is never a house', () {
      expect(QueryParser.parse('warehouse in Zarqa').constraints.type, 'warehouse');
    });

    test('negation is scoped to the feature it precedes', () {
      final c = QueryParser.parse('penthouse in Dabouq with pool but no garden').constraints;
      expect(c.amenities, contains('pool'));
      expect(c.amenities, isNot(contains('garden')));
    });

    test('Arabic-Indic digits are read', () {
      expect(QueryParser.normalizeNumerals('٣ غرف'), '3 غرف');
    });
  });
}

/// Website fixtures the app deliberately reads further, and what it adds.
const _readsMoreThanWebsite = <String, Map<String, Object?>>{
  // "مليون" said as a word: the website needs digits.
  'فيلا للبيع في عبدون مع مسبح وحديقة بحدود مليون دينار': {'budgetMax': 1000000},
};
