import '../../../shared/models/search_constraints.dart';
import '../../../shared/reference/market_data.dart';
import 'spoken_numbers.dart';

/// Deterministic query understanding, ported line for line from the website's
/// lib/aisearch.js `parseQuery`. No model, no network: the sentence is read
/// with the same rules, the same vocabularies and the same place names, so a
/// query typed into the app produces exactly the constraints it would on the
/// website. test/query_parser_test.dart checks that against the website's own
/// output (test/fixtures/parse_query.json).
///
/// Where the JavaScript has a quirk, so does this — parity is the point.
///
/// On top of the website's rules the app reads more of how Jordanians
/// actually ask (marked "App extension" below): spoken numbers ("مية وخمسين
/// ألف", "eighty thousand"), dialect words for renting, budgets and features
/// ("اجار", "ما يتجاوز", "جنينة", "شوفاج"), "about 500 m" as a range, and more
/// spellings of places. Each only ever adds understanding: every query in the
/// website fixtures still reads exactly as it does there.
class ParsedQuery {
  const ParsedQuery({
    required this.constraints,
    required this.lang,
    required this.changed,
    required this.missing,
    required this.text,
  });

  final SearchConstraints constraints;

  /// 'ar' when the query contains Arabic script, else 'en'.
  final String lang;

  /// Keys this query changed, in the order they changed.
  final List<String> changed;

  /// What is still needed for a confident search: 'deal' and/or 'location'.
  final List<String> missing;
  final String text;
}

class QueryParser {
  const QueryParser._();

  static const _arDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _arLetter = r'ء-ي';
  static final _arabicScript = RegExp(r'[؀-ۿ]');

  // Spelled-out counts, longest first (stable), as in the JavaScript.
  static final List<(String, String)> _wordNumbers = () {
    const raw = <(String, String)>[
      ('غرفتين', '2 غرف'),
      ('غرفتان', '2 غرف'),
      ('three', '3'),
      ('seven', '7'),
      ('eight', '8'),
      ('four', '4'),
      ('five', '5'),
      ('nine', '9'),
      ('one', '1'),
      ('two', '2'),
      ('six', '6'),
      ('ten', '10'),
      ('واحدة', '1'),
      ('ثلاث', '3'),
      ('أربع', '4'),
      ('اربع', '4'),
      ('خمس', '5'),
      ('ست', '6'),
      ('سبع', '7'),
      ('ثمان', '8'),
      ('تسع', '9'),
      ('عشر', '10'),
    ];
    final indexed = [for (var i = 0; i < raw.length; i++) (i, raw[i])];
    indexed.sort((a, b) {
      final byLen = b.$2.$1.length - a.$2.$1.length;
      return byLen != 0 ? byLen : a.$1 - b.$1;
    });
    return [for (final e in indexed) e.$2];
  }();

  static final List<(RegExp, String, bool)> _wordNumberRegexes = [
    for (final (word, n) in _wordNumbers)
      _arabicScript.hasMatch(word)
          ? (RegExp('(^|[^$_arLetter])(بال|وال|فال|ال|ب|و|ف|ل|ك)?$word(?![$_arLetter])'), n, true)
          : (RegExp('\\b$word\\b', caseSensitive: false), n, false),
  ];

  static String detectLang(String s) => _arabicScript.hasMatch(s) ? 'ar' : 'en';

  static String normalizeNumerals(String s) {
    var out = s.replaceAllMapped(RegExp('[٠-٩]'), (m) => _arDigits.indexOf(m[0]!).toString());
    for (final (re, n, arabic) in _wordNumberRegexes) {
      out = arabic ? out.replaceAllMapped(re, (m) => '${m[1] ?? ''}${m[2] ?? ''}$n') : out.replaceAll(re, n);
    }
    return out;
  }

  static final _nonPriceUnit = RegExp(
    r'^\s*(?:m2|m²|sqm|square\s*met(?:er|re)s?|متر|م٢|bed(?:room)?s?\b|bath(?:room)?s?\b|br\b|ba\b|غرف|حمام)',
    caseSensitive: false,
  );

  static bool _followedByArea(String text, int end) => _nonPriceUnit.hasMatch(text.substring(end));

  static final _moneyCue = RegExp(
    r'^\s*(?:jod|jd|dinars?|دينار|k\b|m\b|thousand|million|ألف|الف|مليون)',
    caseSensitive: false,
  );

  // ── term matching ────────────────────────────────────────────────────

  static final Map<String, RegExp> _termCache = {};
  static final _escapeChars = RegExp(r'[.*+?^${}()|[\]\\]');
  static final _spaceRun = RegExp("[\\s’']+");

  static RegExp termRegex(String term) {
    return _termCache.putIfAbsent(term, () {
      final esc = term.replaceAllMapped(_escapeChars, (m) => '\\${m[0]}').replaceAll(_spaceRun, "[\\s’']*");
      return _arabicScript.hasMatch(term)
          ? RegExp('(?:^|[^$_arLetter])(?:بال|وال|فال|كال|لل|ال|ب|و|ف|ل|ك)?$esc(?![$_arLetter])')
          : RegExp('\\b$esc(?:e?s)?\\b', caseSensitive: false);
    });
  }

  static final _articlePrefix = RegExp(r'^(?:al|el)[\s-]+', caseSensitive: false);

  /// Place names carry "Al" in their official form but people rarely type it.
  static List<String> _expandTerms(List<String> terms) {
    final out = <String>[];
    for (final t in terms) {
      if (t.isEmpty) continue;
      out.add(t);
      final bare = t.replaceFirst(_articlePrefix, '');
      if (bare != t && bare.length > 2) out.add(bare);
      // App extension: Arabic names said without their article ("صويفية").
      if (t.startsWith('ال') && t.length > 4) out.add(t.substring(2));
    }
    return out;
  }

  /// App extension: spellings and pronunciations people use for places,
  /// beyond the reference data's own alternatives.
  static const Map<String, List<String>> _extraPlaceNames = {
    'jubaiha': ['jbeiha', 'jubeiha', 'jbeha', 'الجبيهة', 'جبيهة'],
    'umuthaina': ['um uthaina', 'umm uthaina', 'um uthayna', 'om uthaina', 'ام اذينة', 'أم أذينة', 'ام اذينه'],
    'tlaalali': ['tla al ali', 'tlaa al ali', 'tla el ali', 'تلاع العلي', 'تلاع علي'],
    'shmeisani': ['shmesani', 'shmaisani', 'shmeisany', 'الشميساني', 'شميساني'],
    'dabouq': ['dabouk', 'daboq'],
    'marj': ['marj al hamam', 'marj el hamam', 'mar al hamam', 'مرج الحمام'],
    'shafabadran': ['shafa badran', 'shafa', 'شفا بدران'],
    'dahiyatrashid': ['dahiet al rasheed', 'dahiyat al rashid', 'rasheed suburb', 'ضاحية الرشيد'],
    'weibdeh': ['luweibdeh', 'lweibdeh', 'jabal al weibdeh', 'اللويبدة', 'لويبدة'],
    'jabalamman': ['jabal amman', 'jabal amman 1st circle', 'جبل عمان'],
    'abdali': ['al abdali', 'boulevard', 'العبدلي', 'عبدلي'],
    'deirghbar': ['deir ghbar', 'dair ghbar', 'دير غبار'],
    'sweifieh': ['swefiyeh', 'sweifiye', 'swefieh', 'صويفية'],
    'khalda': ['khaldaa', 'خلدة'],
    'gardens': ['al gardens', 'gardens street', 'شارع الجاردنز', 'الجاردنز', 'جاردنز'],
  };

  /// Longest match wins; the first matching term of an entry ends that entry.
  static String? _bestMatch(String text, List<(String, List<String>)> entries) {
    String? bestId;
    var bestLen = 0;
    for (final (id, terms) in entries) {
      for (final term in _expandTerms(terms)) {
        if (term.isEmpty || term.length <= bestLen) continue;
        if (termRegex(term).hasMatch(text)) {
          bestId = id;
          bestLen = term.length;
          break;
        }
      }
    }
    return bestId;
  }

  static const Map<String, List<String>> _typeSynonyms = {
    'apartment': [
      'apartment',
      'apt',
      'flat',
      'condo',
      'penthouse',
      'duplex',
      'studio apartment',
      'شقة',
      'شقق',
      'بنتهاوس',
      'دوبلكس',
      'ستوديو',
      // App extension: dialect spellings.
      'استديو',
      'ستديو',
      'طابقية',
    ],
    'villa': ['villa', 'townhouse', 'فيلا', 'فلل', 'فيلات', 'تاون هاوس', 'قصر'],
    'house': ['house', 'home', 'farmhouse', 'bungalow', 'بيت', 'منزل', 'دار', 'بيت مستقل'],
    'land': ['land', 'plot', 'parcel', 'lot', 'أرض', 'ارض', 'قطعة أرض', 'اراضي', 'أراضي'],
    'office': ['office', 'workspace', 'مكتب', 'مكاتب'],
    'shop': ['shop', 'store', 'showroom', 'retail unit', 'محل', 'محلات', 'معرض', 'محل تجاري'],
    'building': ['building', 'apartment building', 'block of flats', 'بناية', 'عمارة', 'بنايات'],
    'chalet': ['chalet', 'شاليه', 'شاليهات'],
    'warehouse': ['warehouse', 'depot', 'مستودع', 'مخزن', 'مستودعات'],
    'farm': ['farm', 'farmland', 'orchard', 'مزرعة', 'مزارع'],
  };

  static final _hoodEntries = [
    for (final n in Market.neighborhoods) (n.id, [n.en, n.ar, ...n.alt, ...?_extraPlaceNames[n.id]]),
  ];
  static final _cityEntries = [
    for (final c in Market.cities) (c.id, [c.en, c.ar, ...c.alt]),
  ];
  static final _typeEntries = [
    for (final t in Market.types) (t.id, [t.en, t.ar, ...?_typeSynonyms[t.id]]),
  ];

  // ── amounts ──────────────────────────────────────────────────────────

  static final _leadingFloat = RegExp(r'^(\d+\.?\d*|\.\d+)');
  static final _thousandTail = RegExp(r'^k\b|thousand|ألف|الف');
  static final _millionTail = RegExp(r'^m\b|million|مليون');

  /// JavaScript's parseFloat over what the regexes capture, then the scale.
  static int? parseAmount(String raw, String? tail) {
    final m = _leadingFloat.firstMatch(raw.replaceAll(',', ''));
    if (m == null) return null;
    var n = double.parse(m[1]!);
    final t = (tail ?? '').toLowerCase();
    if (_thousandTail.hasMatch(t)) {
      n *= 1000;
    } else if (_millionTail.hasMatch(t)) {
      n *= 1000000;
    }
    return _jsRound(n);
  }

  /// Math.round: halves go up, towards positive infinity. Amounts past what
  /// any listing could cost are dropped rather than overflowing an int.
  static int? _jsRound(double n) => n.isFinite && n < 9e15 ? (n + 0.5).floor() : null;

  static final Map<String, List<RegExp>> _dealWords = {
    'rent': [
      RegExp(r'\brent(al|ing)?\b', caseSensitive: false),
      RegExp(r'\bto let\b', caseSensitive: false),
      RegExp(r'\blease\b', caseSensitive: false),
      RegExp('للإيجار'),
      RegExp('للايجار'),
      RegExp('استئجار'),
      RegExp('ايجار'),
      RegExp('إيجار'),
      // App extension: how it is said in Jordan.
      RegExp('(?:^|[^$_arLetter])(?:بال|ال|لل|ل|ب)?اجار'),
      RegExp('استأجر|استاجر|أستأجر|نستأجر|تأجير|مستأجر'),
      RegExp(r'\b(?:yearly|annual(?:ly)?|per year)\b', caseSensitive: false),
      RegExp('سنوي'),
    ],
    'sale': [
      RegExp(r'\bbuy\b', caseSensitive: false),
      RegExp(r'\bfor sale\b', caseSensitive: false),
      RegExp(r'\bpurchase\b', caseSensitive: false),
      RegExp(r'\bown\b', caseSensitive: false),
      RegExp('للبيع'),
      RegExp('شراء'),
      RegExp('اشتري'),
      RegExp('أشتري'),
      RegExp('تملك'),
      // App extension.
      RegExp('(?:^|[^$_arLetter])(?:لل|ل|ب)?بيع(?![$_arLetter])'),
      RegExp('تمليك'),
    ],
  };

  static RegExp _i(String p) => RegExp(p, caseSensitive: false);

  static final Map<String, List<RegExp>> _amenityWords = {
    'garden': [_i('garden'), _i('yard'), RegExp('حديقة'), RegExp('حديقه|جنينة|جنينه')],
    'pool': [_i('pool'), _i('swimming'), RegExp('مسبح'), RegExp('بركة')],
    'parking': [
      _i('parking'),
      _i('garage'),
      RegExp('موقف'),
      RegExp('كراج'),
      RegExp('مواقف'),
      RegExp('كراچ|جراج|باركنج|باركينج'),
    ],
    'balcony': [
      _i('balcon'),
      _i('terrace'),
      RegExp('شرفة'),
      RegExp('بلكونة'),
      RegExp('تراس'),
      RegExp('بلكون|برندة|برنده|فرندة|بالكون'),
    ],
    'elevator': [_i('elevator'), _i(r'\blift\b'), RegExp('مصعد'), RegExp('اسانسير'), RegExp('أسانسير|اصنصير|مصاعد')],
    'furnished': [_i('furnished'), RegExp('مفروش')],
    'security': [_i('security'), _i('guard'), RegExp('حراسة'), RegExp('أمن'), RegExp('حارس|ناطور|نواطير')],
    'heating': [_i('heating'), RegExp('تدفئة'), RegExp('تدفئه|شوفاج|شوفاچ'), _i('central heat')],
    'ac': [_i(r'\ba\/?c\b'), _i('air condition'), RegExp('تكييف'), RegExp('مكيف'), RegExp('كونديشن|سبليت')],
    'solar': [_i('solar'), RegExp('شمسي')],
    'storage': [_i('storage'), RegExp('مستودع صغير'), RegExp('تخزين')],
    'smart': [_i('smart home'), _i('smart'), RegExp('ذكي')],
    'seaview': [_i('sea ?view'), RegExp('إطلالة بحرية'), RegExp('اطلالة بحرية'), RegExp('على البحر')],
    'roof': [_i(r'\broof\b'), _i('rooftop'), RegExp('رووف'), RegExp('سطح')],
  };

  static final List<(RegExp, String)> _styleWords = [
    (_i('modern|contemporary'), 'modern'),
    (RegExp('حديث|عصري|مودرن'), 'modern'),
    (RegExp('مودرن|ستايل حديث'), 'modern'),
    (_i('new|brand ?new|newly built'), 'new'),
    (RegExp('جديد|حديثة البناء'), 'new'),
    (_i('luxur|premium|high[- ]end'), 'luxury'),
    (RegExp('فاخر|فخم'), 'luxury'),
    (_i('quiet|calm'), 'quiet'),
    (RegExp('هادئ'), 'quiet'),
    (_i('investment|yield|rental return'), 'investment'),
    (RegExp('استثمار|عائد'), 'investment'),
  ];

  static final _negator = RegExp(
    r"(?:\bno\b|\bnot\b|\bwithout\b|\bremove\b|\bdrop\b|\bforget\b|\bdon'?t (?:need|want)\b|\bno longer\b|بدون|بلا|مش|ما بدي|ألغِ|الغي|احذف|غير|بلاش|ما بدنا|مش لازم)[^.,;]{0,18}$",
    caseSensitive: false,
  );

  static const _scale = r'(k|m|thousand|million|ألف|الف|مليون)';

  static final _range = _i(
    '(?:between|from|بين|من)\\s*([\\d.,]+)\\s*$_scale?\\s*(?:and|to|until|[-–]|إلى|الى|و)\\s*([\\d.,]+)\\s*$_scale?',
  );
  static final _budget = _i(
    '(?:under|below|max(?:imum)?|up to|less than|budget(?: is| of)?|أقل من|اقل من|بحدود|ميزانيتي|حتى|لغاية'
    // App extension: more ways to set a ceiling, in both languages.
    '|no more than|not more than|not over|within|around|about|approximately|roughly'
    '|ما يتجاوز|ما بيتجاوز|ما يزيد عن|ما يزيد على|ما بزيد عن|لا يزيد عن|مش اكثر من|مش أكثر من|بحد أقصى|بحد اقصى|تحت|حوالي|بحوالي|تقريبا|تقريباً)'
    '\\s*(?:jod|jd|دينار)?\\s*([\\d.,]+)\\s*$_scale?',
  );
  static final _minBudget = _i(
    '(?:over|above|at least|starting (?:from|at)|from|أكثر من|اكثر من|ابتداء من)\\s*(?:jod|jd|دينار)?\\s*([\\d.,]+)\\s*$_scale?\\s*(?:jod|jd|دينار)',
  );
  static final _bareMoney = _i('([\\d.,]+)\\s*$_scale?\\s*(?:jod|jd|dinars?|دينار)');
  static final _revise = _i(
    '(?:increase|raise|bump|actually|instead|change (?:it )?to|make it)\\D{0,18}?([\\d.,]+)\\s*$_scale?|(?:ارفع|زد|خليها)\\D{0,18}?([\\d.,]+)\\s*(ألف|الف|مليون)?',
  );
  static final _monthly = _i(r'(?:per|a|\/)\s*month|monthly|\/mo\b|شهري|بالشهر|شهريا');
  static final _beds = _i(
    r'([\d]+)\s*(?:\+|or more)?\s*-?\s*(?:bed(?:room)?s?|br\b)|(?:غرف(?:ة)? نوم|غرف)\s*([\d]+)|([\d]+)\s*غرف',
  );
  static final _baths = _i(
    r'([\d]+)\s*(?:\+)?\s*-?\s*(?:bath(?:room)?s?|ba\b)|(?:حمام(?:ات)?)\s*([\d]+)|([\d]+)\s*حمام',
  );
  static final _area = _i(r'([\d,]+)\s*(?:m2|m²|sqm|square met(?:er|re)s?|متر)');

  /// App extension: "about 500 m" — a size people want near, not over.
  static final _approx = _i(r'(?:about|around|approximately|roughly|حوالي|بحدود|تقريبا|تقريباً|بحوالي)\s*$');
  static final _internalOnly = _i(r'only .*(this (web)?site|our marketplace|akarat)|فقط .*(الموقع|منصتنا)');

  /// Reads [input], on top of [previous] when refining an earlier search.
  static ParsedQuery parse(String input, [SearchConstraints? previous]) {
    final rawText = input.trim();
    final lang = detectLang(rawText);
    // App extension: spoken numbers first, and "unfurnished" read as "not
    // furnished" so the feature is not added by its own negation.
    final text = normalizeNumerals(
      SpokenNumbers.normalize(rawText).replaceAll(RegExp(r'\bun-?furnished', caseSensitive: false), 'not furnished'),
    );
    final c = _Mutable(previous ?? SearchConstraints.empty);
    final changed = <String>[];

    void set(String key, Object? value) {
      if (c.differs(key, value)) {
        c.assign(key, value);
        changed.add(key);
      }
    }

    bool negatedAt(int index) {
      final from = index - 28 < 0 ? 0 : index - 28;
      return _negator.hasMatch(text.substring(from, index));
    }

    for (final MapEntry(key: deal, value: pats) in _dealWords.entries) {
      if (pats.any((p) => p.hasMatch(text))) {
        set('deal', deal);
        break;
      }
    }

    final hoodHit = _bestMatch(text, _hoodEntries);
    if (hoodHit != null) {
      final n = Market.neighborhood(hoodHit)!;
      set('hood', n.id);
      set('city', n.city);
    }
    final cityHit = _bestMatch(text, _cityEntries);
    if (cityHit != null) {
      if (c.hood != null) {
        final h = Market.neighborhood(c.hood);
        if (h != null && h.city != cityHit) set('hood', null);
      }
      set('city', cityHit);
    }

    final typeHit = _bestMatch(text, _typeEntries);
    if (typeHit != null) set('type', typeHit);
    if (termRegex('studio').hasMatch(text) ||
        termRegex('ستوديو').hasMatch(text) ||
        termRegex('استديو').hasMatch(text) ||
        termRegex('ستديو').hasMatch(text)) {
      set('type', 'apartment');
      set('beds', 1);
    }

    final range = _range.firstMatch(text);
    if (range != null && !_followedByArea(text, range.end)) {
      final lo = parseAmount(range[1]!, range[2]);
      final hi = parseAmount(range[3]!, range[4]);
      if (lo != null && lo != 0 && hi != null && hi != 0) {
        set('budgetMin', lo < hi ? lo : hi);
        set('budgetMax', lo < hi ? hi : lo);
      }
    }

    if (range == null) {
      // App extension: the first cue that is a budget, skipping sizes ("about
      // 500 m ... budget 80 thousand"); the website stops at the first cue.
      final budget =
          _budget.allMatches(text).where((m) => !_followedByArea(text, m.end)).firstOrNull ?? _budget.firstMatch(text);
      if (budget != null && !_followedByArea(text, budget.end)) {
        set('budgetMax', parseAmount(budget[1]!, budget[2]));
      }
      final minB = _minBudget.firstMatch(text);
      if (minB != null) set('budgetMin', parseAmount(minB[1]!, minB[2]));
      if (budget == null && minB == null) {
        final bare = _bareMoney.firstMatch(text);
        if (bare != null) set('budgetMax', parseAmount(bare[1]!, bare[2]));
      }
    }

    final revise = _revise.firstMatch(text);
    if (revise != null) {
      final end = revise.end;
      final tail = text.substring(end);
      final scaled = revise[2] != null || revise[4] != null;
      final v = parseAmount((revise[1] ?? revise[3])!, revise[2] ?? revise[4]);
      final plausible = scaled || _moneyCue.hasMatch(tail) || (v != null && v >= 1000);
      if (v != null && v != 0 && plausible && !_followedByArea(text, end)) set('budgetMax', v);
    }

    if (c.deal == null && _monthly.hasMatch(text)) set('deal', 'rent');

    final beds = _beds.firstMatch(text);
    final bedCount = beds == null ? null : int.tryParse((beds[1] ?? beds[2] ?? beds[3])!);
    if (bedCount != null) set('beds', bedCount);
    final baths = _baths.firstMatch(text);
    final bathCount = baths == null ? null : int.tryParse((baths[1] ?? baths[2] ?? baths[3])!);
    if (bathCount != null) set('baths', bathCount);

    final area = _area.firstMatch(text);
    if (area != null) {
      final n = int.tryParse(area[1]!.replaceAll(',', ''));
      // About 500 m: a little under counts too.
      final approx = _approx.hasMatch(text.substring(area.start < 20 ? 0 : area.start - 20, area.start));
      if (n != null) set('areaMin', approx ? (n * 0.9).round() : n);
    }

    final amen = <String>{...c.amenities};
    for (final MapEntry(key: id, value: pats) in _amenityWords.entries) {
      for (final p in pats) {
        final m = p.firstMatch(text);
        if (m == null) continue;
        if (negatedAt(m.start)) {
          amen.remove(id);
        } else {
          amen.add(id);
        }
        break;
      }
    }
    set('amenities', amen.toList());

    final styles = <String>{...c.styles};
    for (final (p, id) in _styleWords) {
      if (p.hasMatch(text)) styles.add(id);
    }
    set('styles', styles.toList());

    if (_internalOnly.hasMatch(text)) set('internalOnly', true);

    final missing = <String>[if (c.deal == null) 'deal', if (c.city == null && c.hood == null) 'location'];

    return ParsedQuery(constraints: c.freeze(), lang: lang, changed: changed, missing: missing, text: rawText);
  }
}

/// A working copy that [QueryParser.parse] can assign to by key, mirroring the
/// plain object the JavaScript mutates.
class _Mutable {
  _Mutable(SearchConstraints s)
    : deal = s.deal,
      city = s.city,
      hood = s.hood,
      budgetMax = s.budgetMax,
      budgetMin = s.budgetMin,
      beds = s.beds,
      baths = s.baths,
      type = s.type,
      areaMin = s.areaMin,
      amenities = List.of(s.amenities),
      styles = List.of(s.styles),
      internalOnly = s.internalOnly;

  String? deal, city, hood, type;
  int? budgetMax, budgetMin, beds, baths, areaMin;
  List<String> amenities, styles;
  bool internalOnly;

  Object? read(String key) => switch (key) {
    'deal' => deal,
    'city' => city,
    'hood' => hood,
    'type' => type,
    'budgetMax' => budgetMax,
    'budgetMin' => budgetMin,
    'beds' => beds,
    'baths' => baths,
    'areaMin' => areaMin,
    'amenities' => amenities,
    'styles' => styles,
    'internalOnly' => internalOnly,
    _ => throw ArgumentError(key),
  };

  bool differs(String key, Object? value) {
    final current = read(key);
    if (current is List<String> && value is List<String>) {
      if (current.length != value.length) return true;
      for (var i = 0; i < current.length; i++) {
        if (current[i] != value[i]) return true;
      }
      return false;
    }
    return current != value;
  }

  void assign(String key, Object? value) {
    switch (key) {
      case 'deal':
        deal = value as String?;
      case 'city':
        city = value as String?;
      case 'hood':
        hood = value as String?;
      case 'type':
        type = value as String?;
      case 'budgetMax':
        budgetMax = value as int?;
      case 'budgetMin':
        budgetMin = value as int?;
      case 'beds':
        beds = value as int?;
      case 'baths':
        baths = value as int?;
      case 'areaMin':
        areaMin = value as int?;
      case 'amenities':
        amenities = value! as List<String>;
      case 'styles':
        styles = value! as List<String>;
      case 'internalOnly':
        internalOnly = value! as bool;
    }
  }

  SearchConstraints freeze() => SearchConstraints(
    deal: deal,
    city: city,
    hood: hood,
    budgetMax: budgetMax,
    budgetMin: budgetMin,
    beds: beds,
    baths: baths,
    type: type,
    areaMin: areaMin,
    amenities: List.unmodifiable(amenities),
    styles: List.unmodifiable(styles),
    internalOnly: internalOnly,
  );
}
