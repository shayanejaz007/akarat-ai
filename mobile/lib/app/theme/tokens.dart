import 'package:material_ui/material_ui.dart';

export 'typography.dart';

/// Design tokens. Screens read these instead of writing raw values, so the
/// whole app can be re-tuned from one file. See DESIGN_SYSTEM.md.
///
/// Palette: a deep forest green and a refined emerald for action, warm ivory
/// and white surfaces, sand and the brand mark's gold as quiet accents, and
/// Jordan's flag red kept for the few things that should stop the eye — a
/// saved heart, a SOLD sticker, a destructive action.
///
/// Dark is matte black: neutral, untinted blacks a step apart (the page is
/// the brand's matte #0B0B0B, from the splash kit), separated by hairlines
/// rather than shadows, soft off-white text, and the same green and gold as
/// accents.
@immutable
class AkaratColors extends ThemeExtension<AkaratColors> {
  const AkaratColors({
    required this.forest,
    required this.emerald,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.border,
    required this.sand,
    required this.gold,
    required this.red,
    required this.success,
    required this.warning,
    required this.danger,
    required this.onForest,
    required this.scrim,
    required this.shadow,
  });

  /// Deep forest. Primary brand colour, headers, the selected tab.
  final Color forest;

  /// Refined emerald. Calls to action and positive states.
  final Color emerald;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color border;
  final Color sand;

  /// The brand mark's gold. Brand moments only, never body text.
  final Color gold;

  /// Jordanian red, used sparingly.
  final Color red;
  final Color success;
  final Color warning;
  final Color danger;
  final Color onForest;
  final Color scrim;
  final Color shadow;

  static const light = AkaratColors(
    forest: Color(0xFF123C34),
    emerald: Color(0xFF16836D),
    // Clean white pages with soft grey fills, in the manner of the
    // reference design; the warmth stays in the forest and gold.
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F5F3),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF192421),
    inkMuted: Color(0xFF5F6C67),
    inkFaint: Color(0xFF9AA49F),
    border: Color(0xFFE9EAE6),
    sand: Color(0xFFDDD0B8),
    gold: Color(0xFFB0832B),
    red: Color(0xFFCE1126),
    success: Color(0xFF16836D),
    warning: Color(0xFFA9661B),
    danger: Color(0xFFB3261E),
    onForest: Color(0xFFFFFFFF),
    scrim: Color(0x99101A17),
    shadow: Color(0x1A0E2420),
  );

  static const dark = AkaratColors(
    forest: Color(0xFF8FD3BF),
    emerald: Color(0xFF3DB394),
    background: Color(0xFF0B0B0B),
    surface: Color(0xFF141414),
    surfaceMuted: Color(0xFF1C1C1C),
    surfaceRaised: Color(0xFF1F1F1F),
    ink: Color(0xFFEDEDED),
    inkMuted: Color(0xFFA6A6A6),
    inkFaint: Color(0xFF6B6B6B),
    border: Color(0xFF262626),
    sand: Color(0xFF332E26),
    gold: Color(0xFFD9B25E),
    red: Color(0xFFFF5A6A),
    success: Color(0xFF3DB394),
    warning: Color(0xFFE0A050),
    danger: Color(0xFFFF8A80),
    onForest: Color(0xFF07211B),
    scrim: Color(0xB3000000),
    shadow: Color(0x66000000),
  );

  @override
  AkaratColors copyWith() => this;

  @override
  AkaratColors lerp(covariant AkaratColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AkaratColors(
      forest: l(forest, other.forest),
      emerald: l(emerald, other.emerald),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkFaint: l(inkFaint, other.inkFaint),
      border: l(border, other.border),
      sand: l(sand, other.sand),
      gold: l(gold, other.gold),
      red: l(red, other.red),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      onForest: l(onForest, other.onForest),
      scrim: l(scrim, other.scrim),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// 4-point spacing scale, plus two micro-gaps below it.
class Space {
  const Space._();

  /// Between two lines that belong together (a title and its place).
  static const double hair = 2;

  /// Between an icon and its label.
  static const double iconGap = 6;

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Side gutter for every screen.
  static const double gutter = 20;
}

class Radii {
  const Radii._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 30;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius field = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius sheet = BorderRadius.vertical(top: Radius.circular(xl));

  /// Rounded-square icon buttons and icon wells.
  static const BorderRadius tile = BorderRadius.all(Radius.circular(16));
}

class Motion {
  const Motion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Zero when the reader asked the system to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}

class Shadows {
  const Shadows._();
  static List<BoxShadow> card(AkaratColors c) => [
    BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> soft(AkaratColors c) => [
    BoxShadow(
      color: c.shadow.withValues(alpha: c.shadow.a * 0.6),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

extension AkaratThemeX on BuildContext {
  AkaratColors get colors => Theme.of(this).extension<AkaratColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
