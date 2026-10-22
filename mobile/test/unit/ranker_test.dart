import 'package:akarat/core/utils/formatters.dart';
import 'package:akarat/features/ai_search/domain/ranker.dart';
import 'package:akarat/features/ai_search/domain/search_item.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

SearchItem _item(Map<String, Object?> j) => SearchItem(
  id: j['id']! as String,
  titleEn: '',
  titleAr: '',
  deal: j['deal'] as String?,
  type: j['type'] as String?,
  city: j['city'] as String?,
  hood: j['hood'] as String?,
  price: j['price'] as int?,
  beds: j['beds'] as int?,
  baths: j['baths'] as int?,
  area: j['area'] as int?,
  amenities: (j['amen'] as List<Object?>? ?? const []).cast<String>(),
  days: j['days'] as int?,
  checked: j['checked'] as int?,
  source: j['source'] as String?,
  kind: j['kind'] as String?,
);

// The same formatter the fixture generator passes to explain().
String _fmt(num? n, String? deal) {
  if (n == null) return 'Not provided';
  final s = Fmt.number(n);
  return deal == 'rent' ? '$s JOD/mo' : '$s JOD';
}

List<Map<String, Object?>> _reasons(List<MatchReason> list) => [
  for (final r in list) {'kind': r.kind.name, 'text': r.text},
];

void main() {
  final cases = fixtureList('score_listing.json');

  test('score and explanations match the website for ${cases.length} pairs', () {
    for (final c in cases) {
      final constraints = SearchConstraints.fromJson(c['constraints']! as Map<String, Object?>);
      final item = _item(c['item']! as Map<String, Object?>);
      final where = '${item.id} vs ${constraints.toJson()}';
      expect(Ranker.score(item, constraints), c['score'], reason: 'score $where');
      expect(_reasons(Ranker.explain(item, constraints, _fmt, 'en')), c['explain_en'], reason: 'en $where');
      expect(_reasons(Ranker.explain(item, constraints, _fmt, 'ar')), c['explain_ar'], reason: 'ar $where');
    }
  });

  test('a closer match ranks higher', () {
    const want = SearchConstraints(city: 'amman', hood: 'abdoun', beds: 3, budgetMax: 150000, type: 'apartment');
    const exact = SearchItem(
      id: 'a',
      titleEn: '',
      titleAr: '',
      city: 'amman',
      hood: 'abdoun',
      beds: 3,
      price: 140000,
      type: 'apartment',
      days: 1,
    );
    const far = SearchItem(
      id: 'b',
      titleEn: '',
      titleAr: '',
      city: 'irbid',
      beds: 1,
      price: 400000,
      type: 'villa',
      days: 200,
    );
    expect(Ranker.score(exact, want), greaterThan(Ranker.score(far, want)));
  });
}
