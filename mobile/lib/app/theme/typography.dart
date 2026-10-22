import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// The app's typefaces. All SIL Open Font License, bundled (licences in
/// assets/fonts, listed in the app's licence page).
///
/// * Inter for Latin: the closest openly licensed relative of Apple's San
///   Francisco, in two optical sizes like SF Text and SF Display. The display
///   cut, tighter and finer, sets everything from 20 px up.
/// * IBM Plex Sans Arabic for Arabic: the website's Arabic face.
/// * Poppins only for the "Akarat.ai" wordmark, which is part of the logo.
abstract final class AppFonts {
  static const text = 'Inter';
  static const display = 'InterDisplay';
  static const arabic = 'IBMPlexSansArabic';
  static const brand = 'Poppins';
}

/// Inter's own tracking curve ("dynamic metrics"): a touch open at caption
/// sizes, progressively tighter as text grows, as San Francisco does. In
/// logical pixels for [size]. Never applied to Arabic, whose letters join.
double latinTracking(double size) => (-0.0223 + 0.185 * math.exp(-0.1745 * size)) * size;

const _figures = [FontFeature.tabularFigures()];

/// [base] adjusted for text in the other script from the interface: an
/// owner's Arabic title in the English app, or an English one in the Arabic
/// app. Arabic is set in its own face with no tracking (letter-spacing
/// breaks its joins); Latin in Inter with Inter's tracking. Paragraphs
/// ([multiline]) also take that script's line height; single lines keep
/// theirs so cards keep their size.
TextStyle styleForScript(TextStyle base, {required bool rtl, bool multiline = true}) {
  final isArabicFace = base.fontFamily == AppFonts.arabic;
  final size = base.fontSize ?? 14;
  final height = base.height;
  if (rtl && !isArabicFace) {
    return base.copyWith(
      fontFamily: AppFonts.arabic,
      fontFamilyFallback: const [AppFonts.text],
      letterSpacing: 0,
      height: multiline && height != null ? height + 0.22 : height,
    );
  }
  if (!rtl && isArabicFace) {
    return base.copyWith(
      fontFamily: size >= 20 ? AppFonts.display : AppFonts.text,
      fontFamilyFallback: const [AppFonts.arabic],
      letterSpacing: latinTracking(size) * (size >= 20 ? 0.5 : 1),
      height: multiline && height != null ? math.max(1.3, height - 0.22) : height,
    );
  }
  return base;
}

/// The type scale, one place for every text style in the app.
///
/// Sizes follow Apple's iOS scale (large title, title 1–3, headline, body,
/// subheadline, footnote, caption) mapped onto Material's roles. Weights stay
/// light-handed: 600 for titles and labels, 700 only for prices, 400 for
/// reading. Line heights are tight for UI text and generous for paragraphs;
/// Arabic gets more room for its marks and dots in every role.
abstract final class TypeScale {
  static TextTheme textTheme(AkaratColors c, {required bool arabic}) {
    TextStyle s(
      double size,
      FontWeight weight, {
      required double height,
      required double arabicHeight,
      bool display = false,
      Color? color,
    }) => style(
      c,
      size,
      weight,
      height: height,
      arabicHeight: arabicHeight,
      arabic: arabic,
      display: display,
      color: color,
    );

    return TextTheme(
      displayLarge: s(34, FontWeight.w600, height: 1.15, arabicHeight: 1.4, display: true),
      displayMedium: s(30, FontWeight.w600, height: 1.18, arabicHeight: 1.42, display: true),
      displaySmall: s(26, FontWeight.w600, height: 1.2, arabicHeight: 1.45, display: true),
      // A listing's own title.
      headlineLarge: s(26, FontWeight.w600, height: 1.2, arabicHeight: 1.45, display: true),
      // The large title of a screen (Saved, Profile...), folding into the bar.
      headlineMedium: s(32, FontWeight.w600, height: 1.15, arabicHeight: 1.4, display: true),
      // Section titles ("Recently listed", "Facilities").
      headlineSmall: s(21, FontWeight.w600, height: 1.25, arabicHeight: 1.5, display: true),
      titleLarge: s(19, FontWeight.w600, height: 1.3, arabicHeight: 1.5),
      titleMedium: s(17, FontWeight.w600, height: 1.3, arabicHeight: 1.55),
      titleSmall: s(15, FontWeight.w600, height: 1.33, arabicHeight: 1.55),
      bodyLarge: s(16, FontWeight.w400, height: 1.5, arabicHeight: 1.75),
      bodyMedium: s(15, FontWeight.w400, height: 1.47, arabicHeight: 1.7),
      bodySmall: s(13, FontWeight.w400, height: 1.4, arabicHeight: 1.6, color: c.inkMuted),
      // Buttons.
      labelLarge: s(15, FontWeight.w600, height: 1.2, arabicHeight: 1.35),
      labelMedium: s(13, FontWeight.w500, height: 1.25, arabicHeight: 1.4),
      labelSmall: s(11.5, FontWeight.w500, height: 1.25, arabicHeight: 1.4),
    );
  }

  /// One style on the scale: the right face for the language and size,
  /// tracking for Latin only.
  static TextStyle style(
    AkaratColors c,
    double size,
    FontWeight weight, {
    required double height,
    required double arabicHeight,
    required bool arabic,
    bool display = false,
    Color? color,
  }) => TextStyle(
    fontFamily: arabic ? AppFonts.arabic : (display ? AppFonts.display : AppFonts.text),
    // Arabic place names inside English shape in the Arabic face, and Latin
    // inside Arabic (Akarat.ai, JOD) in Inter.
    fontFamilyFallback: arabic ? const [AppFonts.text] : const [AppFonts.arabic],
    fontSize: size,
    fontWeight: weight,
    height: arabic ? arabicHeight : height,
    // The display cut is drawn tighter already: half the text cut's curve.
    letterSpacing: arabic ? 0 : latinTracking(size) * (display ? 0.5 : 1),
    color: color ?? c.ink,
  );

  static AkaratType type(AkaratColors c, {required bool arabic}) {
    TextStyle s(double size, FontWeight weight, {required double height, bool display = false, bool figures = false}) {
      final base = style(
        c,
        size,
        weight,
        height: height,
        arabicHeight: height + 0.15,
        arabic: arabic,
        display: display,
      );
      return figures ? base.copyWith(fontFeatures: _figures) : base;
    }

    return AkaratType(
      priceLarge: s(26, FontWeight.w700, height: 1.15, display: true, figures: true),
      price: s(20, FontWeight.w700, height: 1.2, display: true, figures: true),
      priceSmall: s(16, FontWeight.w700, height: 1.25, figures: true),
      figure: s(19, FontWeight.w600, height: 1.25, figures: true),
      pill: s(13, FontWeight.w600, height: 1.25),
      badge: s(11.5, FontWeight.w600, height: 1.2),
    );
  }
}

/// Text roles beyond Material's: prices, counts and the small type on pills
/// and badges. Read with `context.type`.
@immutable
class AkaratType extends ThemeExtension<AkaratType> {
  const AkaratType({
    required this.priceLarge,
    required this.price,
    required this.priceSmall,
    required this.figure,
    required this.pill,
    required this.badge,
  });

  /// The price on a listing's own page and its bar.
  final TextStyle priceLarge;

  /// A card's price.
  final TextStyle price;

  /// Prices in rows, small cards, map cards and search results.
  final TextStyle priceSmall;

  /// Counts that should line up (dashboard figures).
  final TextStyle figure;

  /// Labels on pills and tags: type, deal, facts, amenities, step counts.
  final TextStyle pill;

  /// The smallest labels: badges on photos.
  final TextStyle badge;

  @override
  AkaratType copyWith({
    TextStyle? priceLarge,
    TextStyle? price,
    TextStyle? priceSmall,
    TextStyle? figure,
    TextStyle? pill,
    TextStyle? badge,
  }) => AkaratType(
    priceLarge: priceLarge ?? this.priceLarge,
    price: price ?? this.price,
    priceSmall: priceSmall ?? this.priceSmall,
    figure: figure ?? this.figure,
    pill: pill ?? this.pill,
    badge: badge ?? this.badge,
  );

  @override
  AkaratType lerp(AkaratType? other, double t) {
    if (other == null) return this;
    return AkaratType(
      priceLarge: TextStyle.lerp(priceLarge, other.priceLarge, t)!,
      price: TextStyle.lerp(price, other.price, t)!,
      priceSmall: TextStyle.lerp(priceSmall, other.priceSmall, t)!,
      figure: TextStyle.lerp(figure, other.figure, t)!,
      pill: TextStyle.lerp(pill, other.pill, t)!,
      badge: TextStyle.lerp(badge, other.badge, t)!,
    );
  }
}

extension AkaratTypeX on BuildContext {
  /// Prices, figures, pill and badge labels: see [AkaratType].
  AkaratType get type => Theme.of(this).extension<AkaratType>()!;
}
