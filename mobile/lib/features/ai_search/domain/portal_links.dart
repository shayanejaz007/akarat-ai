import '../../../core/utils/formatters.dart';
import '../../../shared/models/search_constraints.dart';
import '../../../shared/reference/market_data.dart';

/// Real search URLs on the Jordanian portals, ported from the website's
/// lib/providers.js.
///
/// The app cannot fetch a portal's listings itself — that needs the portal's
/// permission and a server — and inventing listings to fill the gap would
/// break the product's one promise. What it can do honestly is turn the
/// parsed brief into each portal's own filtered results page, and say plainly
/// which parts of the brief that link cannot carry.
class PortalSearch {
  const PortalSearch({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    required this.coverage,
    required this.note,
  });

  final String id;
  final String name;
  final String kind;
  final String url;

  /// "kept/asked", or 'all' when nothing was asked.
  final String coverage;

  /// What the link drops, in the reader's language.
  final String note;
}

class PortalLinks {
  const PortalLinks._();

  // Neighbourhood slugs confirmed against the live site, not derived.
  static const _bayutHoods = {'jabalamman': 'jabal-amman'};
  static const _opensooqCities = ['amman', 'irbid', 'zarqa', 'aqaba', 'madaba', 'salt', 'jerash'];
  static const _bayutCities = ['amman', 'irbid', 'zarqa', 'aqaba'];

  static String _openSooq(SearchConstraints c, String lang) {
    final l = lang == 'ar' ? 'ar' : 'en';
    final city = _opensooqCities.contains(c.city) ? '/${c.city}' : '';
    final kind = c.type == 'apartment' ? 'apartments' : 'property';
    final deal = c.deal == 'rent' ? 'rent' : 'sale';
    var url = 'https://jo.opensooq.com/$l$city/property/$kind-for-$deal';
    final beds = c.beds;
    if (beds != null && beds >= 1 && beds <= 9) url += '/$beds-bedrooms';
    return url;
  }

  static Map<String, bool> _openSooqCarries(SearchConstraints c) => {
    'deal': c.deal != null,
    'city': c.city != null && _opensooqCities.contains(c.city),
    'hood': false,
    'type': c.type == 'apartment',
    'beds': c.beds != null && c.beds! >= 1 && c.beds! <= 9,
    'budget': false,
  };

  static String _bayut(SearchConstraints c, String lang) {
    final l = lang == 'ar' ? 'ar' : 'en';
    final city = _bayutCities.contains(c.city) ? c.city! : 'jordan';
    final kind = c.type == 'apartment'
        ? 'apartments'
        : c.type == 'villa'
        ? 'villas'
        : 'properties';
    final deal = c.deal == 'rent' ? 'for-rent' : 'for-sale';
    final b = c.beds;
    final beds = (c.type == 'apartment' && b != null && b >= 1 && b <= 5) ? '$b-bedroom-' : '';
    final hood = _bayutHoods[c.hood];
    final tail = hood != null ? '$beds$kind-$deal-in-$hood' : '$beds$kind-$deal';
    return 'https://www.bayut.jo/$l/$city/$tail/';
  }

  static Map<String, bool> _bayutCarries(SearchConstraints c) => {
    'deal': c.deal != null,
    'city': c.city != null,
    'hood': _bayutHoods.containsKey(c.hood),
    'type': c.type == 'apartment' || c.type == 'villa',
    'beds': c.type == 'apartment' && c.beds != null && c.beds! >= 1 && c.beds! <= 5,
    'budget': false,
  };

  static String _label(Bilingual? row, String? id, String lang) => row?.label(lang) ?? id ?? '';

  /// A plain-language description of the search, reused for the web search.
  static String describe(SearchConstraints c, String lang) {
    final ar = lang == 'ar';
    final bits = <String>[];
    if (c.beds != null) bits.add(ar ? '${c.beds} غرف نوم' : '${c.beds} bedroom');
    if (c.type != null) {
      bits.add(_label(Market.type(c.type), c.type, lang));
    } else {
      bits.add(ar ? 'عقار' : 'property');
    }
    bits.add(c.deal == 'rent' ? (ar ? 'للإيجار' : 'for rent') : (ar ? 'للبيع' : 'for sale'));
    if (c.hood != null) bits.add(_label(Market.neighborhood(c.hood), c.hood, lang));
    if (c.city != null) bits.add(_label(Market.city(c.city), c.city, lang));
    bits.add(ar ? 'الأردن' : 'Jordan');
    if (c.budgetMax case final max? when max != 0) {
      bits.add('${ar ? 'أقل من ' : 'under '}${Fmt.number(max)}${ar ? ' دينار' : ' JOD'}');
    }
    return bits.join(' ');
  }

  static List<PortalSearch> build(SearchConstraints c, String lang) {
    final ar = lang == 'ar';
    final asked = {
      'deal': c.deal != null,
      'city': c.city != null,
      'hood': c.hood != null,
      'type': c.type != null,
      'beds': c.beds != null,
      'budget': c.budgetMax != null && c.budgetMax != 0,
    };
    final askedKeys = asked.entries.where((e) => e.value).map((e) => e.key).toList();
    final nameOf = {
      'deal': ar ? 'نوع العملية' : 'buy/rent',
      'city': ar ? 'المدينة' : 'city',
      'hood': c.hood != null ? _label(Market.neighborhood(c.hood), c.hood, lang) : (ar ? 'المنطقة' : 'area'),
      'type': ar ? 'نوع العقار' : 'property type',
      'beds': ar ? 'غرف النوم' : 'bedrooms',
      'budget': ar ? 'السعر' : 'price',
    };

    PortalSearch portal(String id, String name, String url, Map<String, bool> carried) {
      final kept = askedKeys.where((k) => carried[k] ?? false).toList();
      final dropped = askedKeys.where((k) => !(carried[k] ?? false)).toList();
      return PortalSearch(
        id: id,
        name: name,
        kind: 'known_marketplace',
        url: url,
        coverage: askedKeys.isEmpty ? 'all' : '${kept.length}/${askedKeys.length}',
        note: dropped.isNotEmpty
            ? (ar
                  ? 'يتجاهل ${dropped.map((k) => nameOf[k]).join('، ')}. حدّدها على الموقع'
                  : 'drops ${dropped.map((k) => nameOf[k]).join(', ')}. Set it on their site')
            : (ar ? 'يحمل طلبك كاملاً' : 'carries your full brief'),
      );
    }

    return [
      portal('opensooq', 'OpenSooq Jordan', _openSooq(c, lang), _openSooqCarries(c)),
      portal('bayut', 'Bayut Jordan', _bayut(c, lang), _bayutCarries(c)),
      PortalSearch(
        id: 'web',
        name: ar ? 'بحث عام في السوق' : 'Wider web search',
        kind: 'general_web_result',
        // Uri.encodeComponent keeps the same unreserved set as
        // encodeURIComponent, so the URL is byte-identical to the website's.
        url: 'https://www.google.com/search?q=${Uri.encodeComponent(describe(c, lang))}',
        coverage: ar ? 'كل الشروط' : 'full brief',
        note: ar ? 'وكلاء ومطوّرون خارج المنصات' : 'agencies and developers beyond the portals',
      ),
    ];
  }
}
