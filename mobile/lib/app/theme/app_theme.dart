import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Material 3 themes built from [AkaratColors], one per language and
/// brightness, with the type scale from typography.dart.
///
/// Arabic is not English with a different font. It gets IBM Plex Sans Arabic
/// first (Inter second, for embedded Latin), looser line height so the joins
/// and dots have room, and no tracking, which would break its joins. English
/// gets Inter first and IBM Plex Sans Arabic as the fallback, so an Arabic
/// place name inside an English sentence still shapes.
class AppTheme {
  const AppTheme._();

  static ThemeData build({required Brightness brightness, required String lang}) {
    final c = brightness == Brightness.dark ? AkaratColors.dark : AkaratColors.light;
    final ar = lang == 'ar';
    final family = ar ? AppFonts.arabic : AppFonts.text;
    final fallback = [if (ar) AppFonts.text else AppFonts.arabic];
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.forest,
      onPrimary: c.onForest,
      primaryContainer: Color.alphaBlend(c.emerald.withValues(alpha: 0.14), c.surface),
      onPrimaryContainer: c.forest,
      secondary: c.emerald,
      onSecondary: brightness == Brightness.dark ? c.onForest : Colors.white,
      secondaryContainer: Color.alphaBlend(c.emerald.withValues(alpha: 0.12), c.surface),
      onSecondaryContainer: c.ink,
      tertiary: c.gold,
      onTertiary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.background,
      surfaceContainer: c.surfaceMuted,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.border,
      outlineVariant: c.border,
      shadow: c.shadow,
      scrim: c.scrim,
      inverseSurface: c.ink,
      onInverseSurface: c.background,
    );

    final text = TypeScale.textTheme(c, arabic: ar);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: family,
      fontFamilyFallback: fallback,
      textTheme: text,
      extensions: [
        c,
        TypeScale.type(c, arabic: ar),
      ],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        // Titles start on the content gutter, not Material's 16.
        titleSpacing: Space.gutter,
        // No titleTextStyle here: large-title bars take headlineMedium when
        // expanded and titleLarge when folded, which a theme-level style
        // would flatten into one size.
        systemOverlayStyle: brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      // The one floating action reads as the brand's primary button.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.forest,
        foregroundColor: c.onForest,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: const StadiumBorder(),
        extendedTextStyle: text.labelLarge,
      ),
      cardTheme: CardThemeData(
        color: c.surfaceMuted,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.forest,
          foregroundColor: c.onForest,
          disabledBackgroundColor: c.inkFaint.withValues(alpha: 0.3),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          textStyle: text.labelLarge,
        ),
      ),
      // The secondary button: a soft grey fill, no outline, like the cards
      // and fields around it. On a grey card, give it the page colour.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surfaceMuted,
          disabledBackgroundColor: c.surfaceMuted.withValues(alpha: 0.6),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          side: BorderSide.none,
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.emerald,
          minimumSize: const Size(48, 44),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.ink, minimumSize: const Size(44, 44)),
      ),
      // Soft filled fields with no outline until focused.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 15),
        hintStyle: text.bodyMedium?.copyWith(color: c.inkFaint),
        labelStyle: text.bodyMedium?.copyWith(color: c.inkMuted),
        floatingLabelStyle: text.bodySmall?.copyWith(color: c.emerald, fontWeight: FontWeight.w600),
        helperStyle: text.bodySmall?.copyWith(color: c.inkMuted),
        errorStyle: text.bodySmall?.copyWith(color: c.danger),
        border: const OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.field,
          borderSide: BorderSide(color: c.emerald, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.field,
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.field,
          borderSide: BorderSide(color: c.danger, width: 1.6),
        ),
      ),
      // One chip style everywhere: no checkmarks (selection is the fill and
      // the emerald edge), a calm surface when idle.
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceMuted,
        selectedColor: Color.alphaBlend(c.emerald.withValues(alpha: 0.14), c.surface),
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(color: s.contains(WidgetState.selected) ? c.emerald.withValues(alpha: 0.6) : c.border),
        ),
        shape: const StadiumBorder(),
        showCheckmark: false,
        labelStyle: text.labelMedium?.copyWith(color: c.ink),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: c.forest, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: c.forest, size: 18),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.inkMuted,
          selectedBackgroundColor: c.forest,
          selectedForegroundColor: c.onForest,
          side: BorderSide(color: c.border),
          textStyle: text.labelLarge,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        showDragHandle: true,
        dragHandleColor: c.border,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.inkMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
        actionTextColor: c.sand,
        shape: const RoundedRectangleBorder(borderRadius: Radii.field),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.emerald, linearTrackColor: c.surfaceMuted),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onForest : c.inkFaint),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.forest : c.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.border),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkMuted,
        textColor: c.ink,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: c.inkMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        minVerticalPadding: Space.sm,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.forest,
        unselectedLabelColor: c.inkMuted,
        indicatorColor: c.forest,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        dividerColor: c.border,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
