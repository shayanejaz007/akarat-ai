import 'package:intl/intl.dart';

/// Display formatting that matches the website.
///
/// Numbers use Western digits with comma grouping in both languages, as the
/// website does (`toLocaleString('en-US')`). Jordanian listings, portals and
/// price tags overwhelmingly write prices this way, and keeping one digit
/// system means a price copied from the app matches the one on the site.
class Fmt {
  const Fmt._();

  static final NumberFormat _grouped = NumberFormat('#,##0', 'en_US');

  static String number(num n) => _grouped.format(n);

  /// `150,000 JOD`, `500 JOD/mo`, `60 JOD/night`; `150,000 دينار`,
  /// `500 دينار شهرياً`, `60 دينار لليلة`.
  static String price(num? amount, {required String lang, bool rent = false, bool night = false}) {
    if (amount == null) return lang == 'ar' ? 'غير متوفر' : 'Not provided';
    final n = number(amount);
    if (lang == 'ar') return night ? '$n دينار لليلة' : (rent ? '$n دينار شهرياً' : '$n دينار');
    return night ? '$n JOD/night' : (rent ? '$n JOD/mo' : '$n JOD');
  }

  /// A listing's price with the period its deal is priced in.
  static String listingPrice(num? amount, {required String lang, required bool rent, required bool daily}) =>
      price(amount, lang: lang, rent: rent, night: daily);

  /// A night as a short date in the reader's language: `Fri 7 Nov` / `الجمعة ٧ تشرين الثاني`.
  static String night(DateTime d, {required String lang}) {
    if (lang == 'ar') {
      const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
      return '${days[d.weekday - 1]} ${d.day} ${_levantineMonths[d.month - 1]}';
    }
    return DateFormat('EEE d MMM', 'en_GB').format(d);
  }

  /// `Month 2026` for a calendar header.
  static String month(DateTime d, {required String lang}) =>
      lang == 'ar' ? '${_levantineMonths[d.month - 1]} ${d.year}' : DateFormat('MMMM y', 'en_GB').format(d);

  /// Compact form for map markers and tight chips: `150K`, `1.2M`.
  static String compactPrice(num amount, {required String lang, bool currency = true}) {
    final String v;
    if (amount >= 1000000) {
      v = '${_trim(amount / 1000000)}M';
    } else if (amount >= 1000) {
      v = '${_trim(amount / 1000)}K';
    } else {
      v = number(amount);
    }
    if (!currency) return v;
    return lang == 'ar' ? '$v د.أ' : '$v JOD';
  }

  static String _trim(num v) {
    final s = v.toStringAsFixed(v >= 100 ? 0 : 1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String area(num sqm, {required String lang}) => lang == 'ar' ? '${number(sqm)} م²' : '${number(sqm)} m²';

  /// Calendar date in the reader's language: `24 Aug 2026` / `24 آب 2026`.
  ///
  /// Arabic uses the Levantine month names Jordan uses (كانون الثاني … آب …
  /// أيلول), as the website's own legal pages do; intl's generic `ar` locale
  /// would print the Egyptian/Gulf ones (يناير … سبتمبر). Western digits in
  /// Arabic too, for the same reason prices use them.
  static String date(DateTime when, {required String lang}) {
    final d = when.toLocal();
    if (lang == 'ar') return '${d.day} ${_levantineMonths[d.month - 1]} ${d.year}';
    return DateFormat.yMMMd('en_GB').format(d);
  }

  static const _levantineMonths = [
    'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', //
    'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
  ];

  /// Whole days since [when], never negative.
  static int daysSince(DateTime when, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(when);
    return diff.isNegative ? 0 : diff.inDays;
  }
}
