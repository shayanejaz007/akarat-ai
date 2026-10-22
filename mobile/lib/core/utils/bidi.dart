import 'package:material_ui/material_ui.dart' show TextDirection;

/// The direction of text the app did not write — listing titles,
/// descriptions, inquiry messages — taken from its first strong letter, as
/// Android and iOS do for their own text views. An Arabic-only title in the
/// English interface then reads right to left with its punctuation in place.
TextDirection directionOf(String text, TextDirection fallback) {
  for (final rune in text.runes) {
    if (_isRtl(rune)) return TextDirection.rtl;
    if (_isLtrLetter(rune)) return TextDirection.ltr;
  }
  return fallback;
}

bool _isRtl(int c) =>
    (c >= 0x0590 && c <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana, Arabic Extended
    (c >= 0xFB1D && c <= 0xFDFF) || // presentation forms A
    (c >= 0xFE70 && c <= 0xFEFF) || // presentation forms B
    (c >= 0x10800 && c <= 0x10FFF); // historic RTL scripts

bool _isLtrLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xC0 && c <= 0x24F) || // Latin-1 and Latin Extended letters
    (c >= 0x370 && c <= 0x52F) || // Greek, Cyrillic
    (c >= 0x1E00 && c <= 0x1FFF);
