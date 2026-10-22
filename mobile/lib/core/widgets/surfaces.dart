import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// A rounded-square icon button: soft grey on the page, white with a shadow
/// over photos, or the brand's dark green as the primary action.
class SquareIconButton extends StatefulWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.style = SquareStyle.soft,
    this.size = 48,
    this.iconColor,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final SquareStyle style;
  final double size;
  final Color? iconColor;

  /// A small count in the corner (active filters).
  final int? badge;

  @override
  State<SquareIconButton> createState() => _SquareIconButtonState();
}

enum SquareStyle { soft, onImage, primary }

class _SquareIconButtonState extends State<SquareIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, shadow) = switch (widget.style) {
      SquareStyle.soft => (c.surfaceMuted, c.ink, false),
      SquareStyle.onImage => (Colors.white, const Color(0xFF16201D), true),
      SquareStyle.primary => (c.forest, c.onForest, false),
    };
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: widget.tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap == null
              ? null
              : () {
                  unawaited(HapticFeedback.selectionClick());
                  widget.onTap!();
                },
          child: AnimatedScale(
            scale: _down && !still ? 0.92 : 1,
            duration: Motion.fast,
            curve: Motion.standard,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: Radii.tile,
                    boxShadow: shadow
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(widget.icon, size: widget.size * 0.46, color: widget.iconColor ?? fg),
                ),
                if ((widget.badge ?? 0) > 0)
                  PositionedDirectional(
                    top: -4,
                    end: -4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.emerald,
                        borderRadius: Radii.chip,
                        border: Border.all(color: c.background, width: 2),
                      ),
                      child: Text(
                        '${widget.badge}',
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small white pill with an icon and a label: badges over photos, stats.
class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.label, this.icon, this.dot, this.dense = false});
  final String label;
  final IconData? icon;

  /// A coloured dot instead of an icon (sale / rent).
  final Color? dot;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF16201D);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: const BoxDecoration(
        // Flat white: no blur to redraw on every frame while lists scroll.
        color: Colors.white,
        borderRadius: Radii.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.iconGap),
          ] else if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: ink),
            const SizedBox(width: Space.iconGap),
          ],
          Text(label, style: (dense ? context.type.badge : context.type.pill).copyWith(color: ink)),
        ],
      ),
    );
  }
}

/// A count with its icon in an outlined pill: "🛏 4".
class SpecPill extends StatelessWidget {
  const SpecPill({super.key, required this.icon, required this.label, this.semanticLabel});
  final IconData icon;
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Radii.chip,
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: c.ink),
            const SizedBox(width: Space.iconGap),
            Text(label, style: context.type.pill),
          ],
        ),
      ),
    );
  }
}

/// A square grey tile: a bold icon over a short label ("4 Bedrooms").
class FacilityTile extends StatelessWidget {
  const FacilityTile({super.key, required this.icon, required this.label, this.width = 104});
  final IconData icon;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      padding: const EdgeInsetsDirectional.fromSTEB(Space.sm, Space.md + 2, Space.xs, Space.md),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: c.ink),
          const SizedBox(height: Space.md),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
        ],
      ),
    );
  }
}
