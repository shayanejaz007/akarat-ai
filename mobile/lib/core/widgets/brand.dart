import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';
import 'segmented_pill.dart';

/// The brand mark on a dark tile, as on the app icon.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.tile = true});
  final double size;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/images/akarat-mark.png',
      height: size * (tile ? 0.72 : 1),
      fit: BoxFit.contain,
      semanticLabel: 'Akarat.ai',
      cacheHeight: (size * 3).round(),
    );
    if (!tile) return mark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFF17170F), borderRadius: BorderRadius.circular(size * 0.26)),
      child: mark,
    );
  }
}

/// Mark plus "Akarat.ai" in Latin type in both languages — it is a name.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.color, this.size = 30});
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        const SizedBox(width: Space.xs),
        Text(
          'Akarat.ai',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: AppFonts.brand,
            fontSize: size * 0.6,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: color ?? c.ink,
          ),
        ),
      ],
    );
  }
}

/// A two-option language switch: English / العربية. Each label is set in
/// its own script's face, whatever the interface language.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key, required this.lang, required this.onChanged, this.onDark = false});
  final String lang;
  final ValueChanged<String> onChanged;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return SegmentedPill<String>(
      onDark: onDark,
      height: 36,
      value: lang,
      onChanged: onChanged,
      segments: const [
        PillSegment(value: 'en', label: 'English'),
        PillSegment(value: 'ar', label: 'العربية'),
      ],
    );
  }
}
