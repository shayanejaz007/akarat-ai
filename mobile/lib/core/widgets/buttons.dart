import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// A full-width primary action that owns its busy state.
///
/// While [onPressed]'s future is running the button shows a spinner and
/// ignores further taps, so a double tap can never submit a form twice.
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.busyLabel,
    this.style = BusyButtonStyle.filled,
    this.expand = true,
  });

  final String label;
  final String? busyLabel;
  final IconData? icon;

  /// In place of [icon], for marks that are not glyphs (a provider's logo).
  final Widget? leading;
  final Future<void> Function()? onPressed;
  final BusyButtonStyle style;
  final bool expand;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

enum BusyButtonStyle { filled, outlined, tonal }

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !_busy;
    final fg = widget.style == BusyButtonStyle.filled ? c.onForest : c.forest;
    final child = AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      child: _busy
          ? Row(
              key: const ValueKey('busy'),
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg)),
                if (widget.busyLabel != null) ...[const SizedBox(width: Space.sm), Text(widget.busyLabel!)],
              ],
            )
          : Row(
              key: const ValueKey('idle'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: Space.sm),
                ] else if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20),
                  const SizedBox(width: Space.xs),
                ],
                Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    final button = switch (widget.style) {
      BusyButtonStyle.filled => FilledButton(onPressed: enabled ? _run : null, child: child),
      BusyButtonStyle.outlined => OutlinedButton(onPressed: enabled ? _run : null, child: child),
      BusyButtonStyle.tonal => FilledButton.tonal(
        onPressed: enabled ? _run : null,
        style: FilledButton.styleFrom(
          backgroundColor: Color.alphaBlend(c.emerald.withValues(alpha: 0.12), c.surface),
          foregroundColor: c.forest,
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(borderRadius: Radii.field),
        ),
        child: child,
      ),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      liveRegion: _busy,
      child: widget.expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Scales down slightly under a finger, for cards and tiles.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.borderRadius = Radii.card});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down && !still ? 0.975 : 1,
        duration: Motion.fast,
        curve: Motion.standard,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A pill showing one constraint or filter, with an optional remove action.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.icon, this.onRemove, this.removeLabel, this.tone});

  final String label;
  final IconData? icon;
  final VoidCallback? onRemove;
  final String? removeLabel;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = tone ?? c.forest;
    return Container(
      padding: EdgeInsetsDirectional.only(
        start: Space.sm,
        end: onRemove == null ? Space.sm : Space.xxs,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.09), c.surface),
        borderRadius: Radii.chip,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: Space.iconGap)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: c.ink),
            ),
          ),
          if (onRemove != null)
            Semantics(
              button: true,
              label: removeLabel,
              child: InkResponse(
                onTap: onRemove,
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: c.inkMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.action, this.onAction, this.padding});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  /// Defaults to the screen gutter.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: Space.gutter),
      // Baseline-aligned, so the action reads as part of the title line
      // rather than floating above or below it.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: context.text.headlineSmall)),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.hair),
                  Text(subtitle!, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              // A quiet grey "See all", as in the reference.
              style: TextButton.styleFrom(
                foregroundColor: c.inkMuted,
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                minimumSize: const Size(44, 44),
              ),
              child: Text(action!, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
            ),
        ],
      ),
    );
  }
}
