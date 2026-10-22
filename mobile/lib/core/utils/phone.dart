/// Phone number normalisation, ported from the website's lib/phone.js.
///
/// Used to turn an owner's free-text contact number into something a dialer
/// and WhatsApp accept, and to validate the number a visitor leaves on an
/// inquiry. E.164 is the target: a plus, the country code, then the national
/// number, digits only, 15 at most.
class PhoneCountry {
  const PhoneCountry(this.id, this.dial, this.en, this.ar, this.minLength, this.maxLength);
  final String id;
  final String dial;
  final String en;
  final String ar;
  final int minLength;
  final int maxLength;

  /// The country's flag, drawn by the system from its two-letter code.
  String get flag => String.fromCharCodes(id.toUpperCase().codeUnits.map((u) => 0x1F1E6 + u - 0x41));

  String name(String lang) => lang == 'ar' ? ar : en;
}

class Phone {
  const Phone._();

  /// Jordan first: it is the market. The rest are where its diaspora and its
  /// buyers dial from. Same list and lengths as the website.
  static const List<PhoneCountry> countries = [
    PhoneCountry('jo', '962', 'Jordan', 'الأردن', 9, 9),
    PhoneCountry('sa', '966', 'Saudi Arabia', 'السعودية', 9, 9),
    PhoneCountry('ae', '971', 'United Arab Emirates', 'الإمارات', 9, 9),
    PhoneCountry('kw', '965', 'Kuwait', 'الكويت', 8, 8),
    PhoneCountry('qa', '974', 'Qatar', 'قطر', 8, 8),
    PhoneCountry('bh', '973', 'Bahrain', 'البحرين', 8, 8),
    PhoneCountry('om', '968', 'Oman', 'عُمان', 8, 8),
    PhoneCountry('us', '1', 'United States', 'الولايات المتحدة', 10, 10),
    PhoneCountry('ca', '1', 'Canada', 'كندا', 10, 10),
    PhoneCountry('gb', '44', 'United Kingdom', 'المملكة المتحدة', 10, 10),
  ];

  static PhoneCountry country(String? id) => countries.firstWhere((c) => c.id == id, orElse: () => countries.first);

  /// Digits only, with Arabic-Indic (٠-٩) and Eastern Arabic-Indic (۰-۹)
  /// numerals folded to 0-9 — an Arabic keyboard types the former.
  static String digitsOf(String? input) {
    final buffer = StringBuffer();
    for (final unit in (input ?? '').runes) {
      if (unit >= 0x0660 && unit <= 0x0669) {
        buffer.writeCharCode(0x30 + unit - 0x0660);
      } else if (unit >= 0x06F0 && unit <= 0x06F9) {
        buffer.writeCharCode(0x30 + unit - 0x06F0);
      } else if (unit >= 0x30 && unit <= 0x39) {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  static String nationalNumber(String? input, PhoneCountry country) {
    var d = digitsOf(input);
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith(country.dial) && d.length > country.dial.length) {
      d = d.substring(country.dial.length);
    }
    return d.replaceFirst(RegExp('^0+'), '');
  }

  /// E.164, or null when what was typed cannot be one.
  static String? toE164(String? input, [String countryId = 'jo']) {
    final c = country(countryId);
    final nsn = nationalNumber(input, c);
    if (nsn.isEmpty) return null;
    if (nsn.length < c.minLength || nsn.length > c.maxLength) return null;
    final full = c.dial + nsn;
    if (full.length > 15) return null;
    return '+$full';
  }

  /// For display: +962 79 123 4567.
  static String pretty(String? input, [String countryId = 'jo']) {
    final c = country(countryId);
    final nsn = nationalNumber(input, c);
    if (nsn.isEmpty) return '+${c.dial}';
    return '+${c.dial} ${_grouped(nsn)}'.trim();
  }

  /// Grouped the way each length is read aloud: 3-3-4 for the ten-digit
  /// countries, 2-3-4 for the nine, 4-4 for the eight.
  static String _grouped(String nsn) {
    final List<String> groups;
    if (nsn.length >= 10) {
      groups = [nsn.substring(0, 3), nsn.substring(3, 6), nsn.substring(6)];
    } else if (nsn.length == 9) {
      groups = [nsn.substring(0, 2), nsn.substring(2, 5), nsn.substring(5)];
    } else if (nsn.length == 8) {
      groups = [nsn.substring(0, 4), nsn.substring(4)];
    } else {
      groups = [nsn];
    }
    return groups.where((g) => g.isNotEmpty).join(' ');
  }

  /// An international number, with or without its plus (Supabase keeps a
  /// user's phone as bare digits), split into one of [countries] and its
  /// national number. Null for a number from anywhere else.
  static ({PhoneCountry country, String national})? split(String? international) {
    final d = digitsOf(international);
    if (d.isEmpty) return null;
    for (final c in countries) {
      if (!d.startsWith(c.dial)) continue;
      final nsn = d.substring(c.dial.length);
      if (nsn.length >= c.minLength && nsn.length <= c.maxLength) return (country: c, national: nsn);
    }
    return null;
  }

  /// A stored international number for display: +962 79 123 4567, or the
  /// digits behind a plus for a country not on the list. Empty for none.
  static String display(String? international) {
    final parts = split(international);
    if (parts != null) return '+${parts.country.dial} ${_grouped(parts.national)}';
    final d = digitsOf(international);
    return d.isEmpty ? '' : '+$d';
  }

  /// A dialable `tel:` target for a number exactly as an owner typed it.
  ///
  /// The website builds its tel: link by stripping everything but digits and
  /// a leading plus; this does the same, and returns null for something that
  /// clearly is not a phone number.
  static String? dialable(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final plus = trimmed.startsWith('+');
    final digits = digitsOf(trimmed);
    if (digits.length < 6 || digits.length > 15) return null;
    return plus ? '+$digits' : digits;
  }

  /// A wa.me target. WhatsApp needs the full international number without
  /// the plus; a Jordanian number written locally (07…) is assumed Jordanian,
  /// which is what an owner on a Jordanian marketplace means by it.
  static String? whatsappTarget(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    final digits = digitsOf(trimmed);
    if (trimmed.startsWith('+') || digits.startsWith('00')) {
      final intl = digits.startsWith('00') ? digits.substring(2) : digits;
      return intl.length >= 8 && intl.length <= 15 ? intl : null;
    }
    final e164 = toE164(trimmed, 'jo');
    return e164?.substring(1);
  }
}
