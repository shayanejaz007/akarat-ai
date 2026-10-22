import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

class PillSegment<T> {
  const PillSegment({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// The app's one segmented control: a quiet track with a white thumb that
/// slides to the selection, in the manner of iOS. Used for Buy/Rent, tab
/// switches, language and appearance, so every "pick one of a few" looks and
/// moves the same way.
///
/// [expand] fills the available width with equal segments; otherwise every
/// segment is as wide as the widest label. [onDark] is for use over a photo.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.onDark = false,
    this.height = 40,
  });

  final List<PillSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;
  final bool onDark;
  final double height;

  static const _pad = 3.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textStyle = context.text.labelLarge!;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final dir = Directionality.of(context);
    final index = math.max(0, segments.indexWhere((s) => s.value == value));

    double natural(PillSegment<T> s) {
      final tp = TextPainter(
        text: TextSpan(text: s.label, style: textStyle),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return tp.width + (s.icon != null ? 24 : 0) + 32;
    }

    // In the dark theme surface and track are a shade apart, so the thumb
    // is lifted well clear of the track, as iOS does.
    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    final track = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : (darkTheme ? Color.alphaBlend(Colors.white.withValues(alpha: 0.05), c.background) : c.surfaceMuted);
    final thumb = onDark
        ? Colors.white
        : (darkTheme ? Color.alphaBlend(Colors.white.withValues(alpha: 0.2), c.surface) : c.surface);
    final selectedFg = onDark ? const Color(0xFF123C34) : c.ink;
    final idleFg = onDark ? Colors.white.withValues(alpha: 0.92) : c.inkMuted;
    final duration = Motion.of(context, Motion.normal);
    final h = math.max(height, 34 * scaler.scale(1));

    return LayoutBuilder(
      builder: (context, box) {
        final segWidth = expand && box.hasBoundedWidth
            ? (box.maxWidth - _pad * 2) / segments.length
            : segments.map(natural).reduce(math.max);
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: Container(
            width: segWidth * segments.length + _pad * 2,
            height: h,
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(color: track, borderRadius: Radii.chip),
            child: Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: duration,
                  curve: Motion.emphasized,
                  start: segWidth * index,
                  top: 0,
                  bottom: 0,
                  width: segWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: thumb,
                      borderRadius: Radii.chip,
                      boxShadow: onDark
                          ? null
                          : [
                              BoxShadow(color: c.shadow, blurRadius: 6, offset: const Offset(0, 2)),
                              BoxShadow(color: c.shadow.withValues(alpha: 0.04), blurRadius: 1),
                            ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < segments.length; i++)
                      SizedBox(
                        width: segWidth,
                        child: Semantics(
                          button: true,
                          selected: i == index,
                          inMutuallyExclusiveGroup: true,
                          label: segments[i].label,
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (i == index) return;
                              unawaited(HapticFeedback.selectionClick());
                              onChanged(segments[i].value);
                            },
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: duration,
                                style: textStyle.copyWith(
                                  color: i == index ? selectedFg : idleFg,
                                  fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                                ),
                                child: MediaQuery(
                                  data: MediaQuery.of(context).copyWith(textScaler: scaler),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (segments[i].icon != null) ...[
                                        Icon(segments[i].icon, size: 17, color: i == index ? selectedFg : idleFg),
                                        const SizedBox(width: Space.iconGap),
                                      ],
                                      Flexible(
                                        child: Text(segments[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
