import 'package:flutter/services.dart';

/// Digits only, with Arabic-Indic (٠-٩) and Eastern Arabic-Indic (۰-۹)
/// numerals folded to 0-9 as they are typed. An Arabic keyboard produces
/// the former; a plain digits-only filter would silently swallow them.
class WesternDigitsFormatter extends TextInputFormatter {
  const WesternDigitsFormatter({this.maxLength = 9});
  final int maxLength;

  static String fold(String input) {
    final b = StringBuffer();
    for (final r in input.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + r - 0x06F0);
      } else if (r >= 0x30 && r <= 0x39) {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = fold(newValue.text);
    if (text.length > maxLength) text = text.substring(0, maxLength);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
