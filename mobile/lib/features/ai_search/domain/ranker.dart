import '../../../shared/models/search_constraints.dart';
import '../../../shared/reference/market_data.dart';
import 'search_item.dart';

/// Deterministic ranking and match explanations, ported from the website's
/// lib/aisearch.js `scoreListing` and `explain`. The scorer weighs retrieved
/// facts only; nothing is inferred about a property that its source did not
/// publish. test/ranker_test.dart compares both against the website.
///
/// One quirk carried over on purpose: JavaScript reads a missing price as 0
/// in `price / budget` and `price <= budget`, so an external row with no
/// price counts as within budget. Changing that is a website decision first.
class Ranker {
  const Ranker._();

  static const _weights = {
    'budget': 26.0,
    'location': 20.0,
    'beds': 15.0,
    'baths': 10.0,
    'type': 12.0,
    'area': 8.0,
    'amenities': 9.0,
    'freshness': 5.0,
    'source': 3.0,
  };

  static int score(SearchItem item, SearchConstraints c) {
    var got = 0.0;
    var possible = 0.0;
    void add(String weight, double frac) {
      final w = _weights[weight]!;
      possible += w;
      got += w * frac;
    }

    final price = item.price ?? 0;
    if (c.budgetMax case final max? when max != 0) {
      final over = price / max;
      add(
        'budget',
        over <= 1
            ? 1
            : over <= 1.05
            ? 0.6
            : over <= 1.15
            ? 0.25
            : 0,
      );
    }
    if (c.hood != null) {
      add(
        'location',
        item.hood == c.hood
            ? 1
            : item.city == c.city
            ? 0.55
            : 0,
      );
    } else if (c.city != null) {
      add('location', item.city == c.city ? 1 : 0);
    }

    if (c.beds case final want?) {
      final b = item.beds;
      add(
        'beds',
        b == null
            ? 0.3
            : b >= want
            ? 1
            : b == want - 1
            ? 0.4
            : 0,
      );
    }
    if (c.baths case final want?) {
      final b = item.baths;
      add(
        'baths',
        b == null
            ? 0.3
            : b >= want
            ? 1
            : b == want - 1
            ? 0.4
            : 0,
      );
    }
    if (c.type != null) add('type', item.type == c.type ? 1 : 0);
    if (c.areaMin case final min?) {
      final a = item.area;
      add(
        'area',
        a == null
            ? 0.3
            : a >= min
            ? 1
            : a >= min * 0.85
            ? 0.5
            : 0,
      );
    }
    if (c.amenities.isNotEmpty) {
      final have = c.amenities.where(item.amenities.contains).length;
      add('amenities', have / c.amenities.length);
    }
    final days = item.isExternal ? (item.checked ?? 90) : item.days;
    add(
      'freshness',
      days == null
          ? 0.15
          : days <= 7
          ? 1
          : days <= 30
          ? 0.7
          : days <= 60
          ? 0.4
          : 0.15,
    );
    add('source', item.isExternal ? (Market.sourceConfidence[item.kind] ?? 0.5) : 1);

    final score = possible == 0 ? 50 : ((got / possible) * 100 + 0.5).floor();
    return score.clamp(1, 100);
  }

  /// Why an item does or does not match, in the reader's language.
  /// [fmt] formats an amount for a deal ('rent' adds the monthly suffix).
  static List<MatchReason> explain(
    SearchItem item,
    SearchConstraints c,
    String Function(num? amount, String? deal) fmt,
    String lang,
  ) {
    final ar = lang == 'ar';
    final out = <MatchReason>[];
    final price = item.price ?? 0;

    if (c.budgetMax case final max? when max != 0) {
      if (price <= max) {
        out.add(
          MatchReason.good(
            ar
                ? '${fmt(item.price, item.deal)}. داخل ميزانيتك ${fmt(max, null)}'
                : '${fmt(item.price, item.deal)}. Within your ${fmt(max, null)} budget',
          ),
        );
      } else {
        final over = ((price / max - 1) * 100 + 0.5).floor();
        out.add(
          MatchReason.warn(
            ar
                ? '${fmt(item.price, item.deal)}. أعلى من ميزانيتك بنسبة $over%'
                : '${fmt(item.price, item.deal)}. $over% above your budget',
          ),
        );
      }
    }
    if (c.beds case final want?) {
      final b = item.beds;
      if (b == null) {
        out.add(MatchReason.bad(ar ? 'عدد غرف النوم غير متوفر من المصدر' : 'Bedrooms not provided by the source'));
      } else if (b > want) {
        out.add(
          MatchReason.good(ar ? '$b غرف نوم. أكثر من طلبك ($want+)' : '$b bedrooms. Exceeds your $want+ requirement'),
        );
      } else if (b == want) {
        out.add(MatchReason.good(ar ? '$b غرف نوم. مطابق تماماً' : '$b bedrooms. Exact match'));
      } else {
        out.add(
          MatchReason.warn(ar ? '$b غرف نوم. أقل بغرفة واحدة من طلبك' : '$b bedrooms. One short of your requirement'),
        );
      }
    }
    if (c.baths case final want?) {
      final b = item.baths;
      if (b == null) {
        out.add(MatchReason.bad(ar ? 'عدد الحمامات غير متوفر من المصدر' : 'Bathrooms not provided by the source'));
      } else {
        final meets = b >= want;
        final text = ar
            ? '$b حمام. ${meets ? 'يلبي' : 'أقل من'} طلبك ($want+)'
            : '$b bathrooms. ${meets ? 'Meets' : 'Below'} your $want+ requirement';
        out.add(meets ? MatchReason.good(text) : MatchReason.warn(text));
      }
    }
    if (c.areaMin case final min?) {
      final a = item.area;
      if (a == null) {
        out.add(MatchReason.bad(ar ? 'المساحة غير متوفرة من المصدر' : 'Area not provided by the source'));
      } else {
        final meets = a >= min;
        final text = ar
            ? '$a م². ${meets ? 'يلبي' : 'أقل من'} طلبك ($min+ م²)'
            : '$a m². ${meets ? 'Meets' : 'Below'} your $min+ m² requirement';
        out.add(meets ? MatchReason.good(text) : MatchReason.warn(text));
      }
    }
    if (c.amenities.isNotEmpty) {
      final have = c.amenities.where(item.amenities.contains).toList();
      final miss = c.amenities.where((a) => !item.amenities.contains(a)).toList();
      String label(String id) {
        final row = Market.amenity(id);
        if (row == null) return id;
        return ar ? row.ar : row.en.toLowerCase();
      }

      if (have.isNotEmpty) {
        out.add(MatchReason.good(ar ? 'يتضمن ${have.map(label).join('، ')}' : 'Has ${have.map(label).join(', ')}'));
      }
      if (miss.isNotEmpty) {
        final names = miss.map(label).join(ar ? '، ' : ', ');
        final text = ar
            ? '$names ${item.isExternal ? 'غير مذكور من المصدر' : 'غير مذكور'}'
            : '$names ${item.isExternal ? 'not listed by the source' : 'not listed'}';
        out.add(item.isExternal ? MatchReason.bad(text) : MatchReason.warn(text));
      }
    }
    if (item.isExternal) {
      final checked = item.checked;
      if (checked == null) {
        out.add(MatchReason.bad(ar ? 'وقت آخر تحقق غير متوفر' : 'Last checked date not provided'));
      } else {
        final text = checked == 0
            ? (ar ? 'تم التحقق من المصدر اليوم' : 'Checked on the source today')
            : (ar ? 'تم التحقق من المصدر قبل $checked أيام' : 'Checked on the source $checked days ago');
        out.add(checked <= 7 ? MatchReason.good(text) : MatchReason.plain(text));
      }
    } else if (item.days case final days?) {
      final text = days == 0
          ? (ar ? 'أُضيف اليوم' : 'Listed today')
          : (ar ? 'أُضيف قبل $days أيام' : 'Listed $days days ago');
      out.add(days <= 14 ? MatchReason.good(text) : MatchReason.plain(text));
    } else {
      out.add(MatchReason.bad(ar ? 'تاريخ الإضافة غير متوفر' : 'Listing date not provided'));
    }
    return out;
  }
}

enum ReasonKind { good, ok, warn, bad, plain }

class MatchReason {
  const MatchReason(this.kind, this.text);
  const MatchReason.good(this.text) : kind = ReasonKind.good;
  const MatchReason.warn(this.text) : kind = ReasonKind.warn;
  const MatchReason.bad(this.text) : kind = ReasonKind.bad;
  const MatchReason.plain(this.text) : kind = ReasonKind.plain;

  final ReasonKind kind;
  final String text;
}
