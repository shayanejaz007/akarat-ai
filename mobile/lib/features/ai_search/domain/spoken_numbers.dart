/// Numbers said in words, as people type them in a hurry and as speech
/// recognition writes them down: "مية وخمسين ألف", "ربع مليون", "خمسمية متر",
/// "eighty thousand", "a hundred and fifty thousand", "two and a half million".
///
/// A run of number words becomes digits only when it is clearly an amount or
/// a size: it has a scale (thousand, million) or is followed by a currency or
/// an area unit. "مية" alone (water, in Jordanian) and "three bedrooms" are
/// left to the parser's own rules.
class SpokenNumbers {
  const SpokenNumbers._();

  // ── Arabic ───────────────────────────────────────────────────────────

  static const Map<String, int> _arUnits = {
    'واحد': 1,
    'واحدة': 1,
    'وحدة': 1,
    'اثنين': 2,
    'اثنان': 2,
    'ثنتين': 2,
    'اتنين': 2,
    'تنين': 2,
    'اثنتين': 2,
    'ثلاث': 3,
    'ثلاثة': 3,
    'تلات': 3,
    'تلاتة': 3,
    'ثلاثه': 3,
    'اربع': 4,
    'أربع': 4,
    'اربعة': 4,
    'أربعة': 4,
    'اربعه': 4,
    'خمس': 5,
    'خمسة': 5,
    'خمسه': 5,
    'ست': 6,
    'ستة': 6,
    'سته': 6,
    'سبع': 7,
    'سبعة': 7,
    'سبعه': 7,
    'ثمان': 8,
    'ثماني': 8,
    'ثمانية': 8,
    'تمن': 8,
    'تمانية': 8,
    'تمنية': 8,
    'تسع': 9,
    'تسعة': 9,
    'تسعه': 9,
    'عشر': 10,
    'عشرة': 10,
    'عشره': 10,
    'احدعش': 11,
    'إحدى عشر': 11,
    'اطنعش': 12,
    'اثنا عشر': 12,
    'تلطعش': 13,
    'ثلاثة عشر': 13,
    'اربعطعش': 14,
    'خمسطعش': 15,
    'ستطعش': 16,
    'سبعطعش': 17,
    'تمنطعش': 18,
    'تسعطعش': 19,
    'عشرين': 20,
    'عشرون': 20,
    'ثلاثين': 30,
    'تلاتين': 30,
    'ثلاثون': 30,
    'اربعين': 40,
    'أربعين': 40,
    'أربعون': 40,
    'خمسين': 50,
    'خمسون': 50,
    'ستين': 60,
    'ستون': 60,
    'سبعين': 70,
    'سبعون': 70,
    'ثمانين': 80,
    'تمانين': 80,
    'ثمانون': 80,
    'تسعين': 90,
    'تسعون': 90,
  };

  static const Map<String, int> _arHundreds = {
    'مية': 100,
    'مئة': 100,
    'مائة': 100,
    'ميه': 100,
    'ميتين': 200,
    'مئتين': 200,
    'مائتين': 200,
    'مئتان': 200,
    'ثلاثمية': 300,
    'تلتمية': 300,
    'ثلاثمئة': 300,
    'ثلاثمائة': 300,
    'اربعمية': 400,
    'أربعمية': 400,
    'أربعمئة': 400,
    'اربعمائة': 400,
    'أربعمائة': 400,
    'خمسمية': 500,
    'خمسمئة': 500,
    'خمسمائة': 500,
    'ستمية': 600,
    'ستمئة': 600,
    'ستمائة': 600,
    'سبعمية': 700,
    'سبعمئة': 700,
    'سبعمائة': 700,
    'ثمانمية': 800,
    'تمنمية': 800,
    'ثمانمئة': 800,
    'ثمانمائة': 800,
    'تسعمية': 900,
    'تسعمئة': 900,
    'تسعمائة': 900,
  };

  static const Map<String, int> _arScales = {
    'ألف': 1000,
    'الف': 1000,
    'آلاف': 1000,
    'الاف': 1000,
    'ألاف': 1000,
    'مليون': 1000000,
    'ملايين': 1000000,
  };

  /// Scales that carry their own count: "ألفين" is two thousand.
  static const Map<String, int> _arDualScales = {'ألفين': 2000, 'الفين': 2000, 'مليونين': 2000000};

  static const Map<String, double> _arFractions = {'ربع': 0.25, 'نص': 0.5, 'نصف': 0.5};

  // ── English ──────────────────────────────────────────────────────────

  static const Map<String, int> _enUnits = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  static const Map<String, int> _enScales = {'thousand': 1000, 'million': 1000000};

  static final _arLetters = RegExp(r'[ء-ي]');
  static final _token = RegExp(r'[A-Za-z]+|[ء-ي]+|\d+(?:\.\d+)?|\S');

  /// What makes a run of number words an amount or a size when it has no
  /// scale of its own.
  static final _unitAfter = RegExp(
    r'^\s*(?:jod|jd|dinars?|دينار|دنانير|m2|m²|sqm|square|متر|م٢|م2)',
    caseSensitive: false,
  );

  static String normalize(String text) {
    // Arabic-Indic digits first, so "٨٠ ألف" reads as one amount.
    final input = text.replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}');
    final tokens = _token.allMatches(input).toList();
    if (tokens.isEmpty) return input;
    final out = StringBuffer();
    var cursor = 0;
    var i = 0;
    while (i < tokens.length) {
      final run = _readRun(tokens, i);
      if (run == null) {
        i++;
        continue;
      }
      final (end, value, scaled) = run;
      final after = input.substring(tokens[end - 1].end);
      if (!scaled && !_unitAfter.hasMatch(after)) {
        i = end;
        continue;
      }
      out
        ..write(input.substring(cursor, tokens[i].start))
        ..write(_format(value));
      cursor = tokens[end - 1].end;
      i = end;
    }
    out.write(input.substring(cursor));
    return out.toString();
  }

  static String _format(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// Reads the longest run of number words from [start]: (end, value, has a
  /// scale). Null when [start] is not a number word.
  static (int, double, bool)? _readRun(List<RegExpMatch> tokens, int start) {
    double total = 0;
    double current = 0;
    var scaled = false;
    var words = 0;
    var i = start;
    var lastEnd = start;
    while (i < tokens.length) {
      var t = tokens[i][0]!;
      final lower = t.toLowerCase();
      // Joiners between number words: "and", "و" (also as a prefix), "a".
      if (words > 0 && (lower == 'and' || t == 'و')) {
        i++;
        continue;
      }
      // "وخمسين", "ونص": the joiner written onto the next number word.
      if (_arLetters.hasMatch(t) && t.length > 2 && t.startsWith('و') && _isArNumberWord(t.substring(1))) {
        t = t.substring(1);
      }
      if (lower == 'a' || lower == 'an') {
        // "a hundred", "a million", "half a million", "two and a half".
        if (i + 1 < tokens.length) {
          final next = tokens[i + 1][0]!.toLowerCase();
          if (next == 'hundred' || _enScales.containsKey(next)) {
            current = current == 0 ? 1 : current;
            i++;
            continue;
          }
          if (next == 'half' && words > 0) {
            i++;
            continue;
          }
        }
        if (words == 0) return null;
        break;
      }
      final digits = double.tryParse(t);
      final ar = _arValue(t);
      if (digits != null && words == 0) {
        // A figure followed by a spoken scale: "2 مليون", "1.5 million".
        if (i + 1 < tokens.length && _scaleOf(tokens[i + 1][0]!) != null) {
          current = digits;
          words++;
          i++;
          lastEnd = i;
          continue;
        }
        return null;
      }
      if (lower == 'hundred') {
        current = (current == 0 ? 1 : current) * 100;
      } else if (lower == 'half' || _arFractions.containsKey(t)) {
        // "half a million", "نص مليون", "ربع مليون", and "مليون ونص".
        final f = lower == 'half' ? 0.5 : _arFractions[t]!;
        if (scaled && current == 0 && total > 0) {
          total += f * _lastScale(total);
        } else {
          current += f;
        }
      } else if (_scaleOf(t) case final scale?) {
        if (_arDualScales.containsKey(t)) {
          total += current == 0 ? scale.toDouble() : current * scale / 2;
        } else {
          total += (current == 0 ? 1 : current) * scale;
        }
        current = 0;
        scaled = true;
      } else if (_enUnits[lower] case final n?) {
        current += n;
      } else if (ar != null) {
        current += ar;
      } else {
        break;
      }
      words++;
      i++;
      lastEnd = i;
    }
    if (words == 0) return null;
    final value = total + current;
    // A lone unit ("three") or fraction is the parser's business, not ours.
    if (value <= 0) return null;
    return (lastEnd, value, scaled);
  }

  static int? _arValue(String t) => _arUnits[t] ?? _arHundreds[t];

  static bool _isArNumberWord(String t) =>
      _arValue(t) != null || _arScales.containsKey(t) || _arDualScales.containsKey(t) || _arFractions.containsKey(t);

  static int? _scaleOf(String t) => _enScales[t.toLowerCase()] ?? _arScales[t] ?? _arDualScales[t];

  /// The scale of the last whole amount, for "مليون ونص" (1.5 million).
  static double _lastScale(double total) => total >= 1000000 ? 1000000 : 1000;
}
