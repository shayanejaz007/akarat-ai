import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheet, CupertinoActionSheetAction, CupertinoDialogAction, showCupertinoModalPopup;
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// Width discipline. Reading content never runs wider than [reading]; card
/// grids add columns as the screen widens instead of stretching cards.
class Layout {
  const Layout._();

  /// Comfortable measure for text, forms and settings.
  static const double reading = 720;

  /// Widest a grid of cards may get before it is centred.
  static const double grid = 1180;

  /// Horizontal padding that keeps content at most [max] wide, centred, and
  /// never closer to the edge than the gutter.
  static EdgeInsets inset(BuildContext context, {double max = reading, double top = 0, double bottom = 0}) {
    final w = MediaQuery.sizeOf(context).width;
    final side = math.max(Space.gutter, (w - max) / 2);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  /// Card columns for the available width: 1 on phones, 2 on small tablets,
  /// 3 from 900 px.
  static int columns(double width) => width >= 900 ? 3 : (width >= 600 ? 2 : 1);

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;
}

/// Centres [child] at a readable width.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.max = Layout.reading});
  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: child,
    ),
  );
}

/// Cards one per row on phones, two or three per row on wider screens, so a
/// card keeps its proportions instead of stretching to the window. Rows take
/// the height of their tallest card.
class SliverCardList extends StatelessWidget {
  const SliverCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.rowGap = Space.xl,
    this.columnGap = Space.md,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double rowGap;
  final double columnGap;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // Decided on the window, not the padded extent, so the breakpoints
        // match every other screen.
        final cols = Layout.columns(MediaQuery.sizeOf(context).width);
        final rows = (itemCount / cols).ceil();
        return SliverList.separated(
          itemCount: rows,
          separatorBuilder: (_, _) => SizedBox(height: rowGap),
          itemBuilder: (context, r) {
            if (cols == 1) return itemBuilder(context, r);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < cols; k++) ...[
                  if (k > 0) SizedBox(width: columnGap),
                  Expanded(child: r * cols + k < itemCount ? itemBuilder(context, r * cols + k) : const SizedBox()),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// A large-title header, as on iOS: the title sits big on the content's
/// start edge and fades into the bar as the page scrolls. [bottom] stays
/// pinned underneath (filters, segmented control). Drawn here rather than
/// with Material's large bar, so the title lands on the same edge whether or
/// not there is a back button.
class LargeTitleBar extends StatelessWidget {
  const LargeTitleBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.contentMax = Layout.reading,
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;

  /// The width the page's content is held to, so the title starts where the
  /// content does on a tablet too.
  final double contentMax;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final start = Layout.inset(context, max: contentMax).left;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final large = context.text.headlineMedium!;
    final titleBlock = 12 + large.fontSize! * (large.height ?? 1.2) * scale + 8;
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    return SliverAppBar(
      pinned: true,
      leading: leading,
      expandedHeight: kToolbarHeight + titleBlock + bottomHeight,
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      // A hairline shadow once content scrolls beneath, as iOS draws one.
      scrolledUnderElevation: 0.6,
      shadowColor: c.ink.withValues(alpha: 0.5),
      title: _FoldedTitle(title: title),
      actions: [
        ...?actions,
        const SizedBox(width: Space.xs),
      ],
      flexibleSpace: _OpenTitle(title: title, start: start, bottom: bottomHeight),
      bottom: bottom,
    );
  }
}

/// How far the bar is folded: 0 open, 1 closed.
double _folded(BuildContext context) {
  final s = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
  if (s == null || s.maxExtent == s.minExtent) return 1;
  return (1 - (s.currentExtent - s.minExtent) / (s.maxExtent - s.minExtent)).clamp(0.0, 1.0);
}

class _FoldedTitle extends StatelessWidget {
  const _FoldedTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = _folded(context);
    // Appears only in the last stretch of the fold, as the big one goes.
    final opacity = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
    );
  }
}

class _OpenTitle extends StatelessWidget {
  const _OpenTitle({required this.title, required this.start, required this.bottom});
  final String title;
  final double start;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final t = _folded(context);
    final opacity = (1 - t / 0.6).clamp(0.0, 1.0);
    return Stack(
      children: [
        PositionedDirectional(
          start: start,
          end: start,
          bottom: bottom + 8,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, t * -8),
              child: Semantics(
                header: true,
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineMedium),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// iOS-style grouped list: rows on one rounded surface, hairline dividers
/// inset past the icon, an optional small caption above.
class GroupedSection extends StatelessWidget {
  const GroupedSection({super.key, required this.children, this.title, this.footer, this.dividerIndent = 56});

  final String? title;
  final String? footer;
  final List<Widget> children;

  /// Where the hairline between rows starts: past the icon by default.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, indent: dividerIndent, color: c.background.withValues(alpha: 0.9)));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Space.md, 0, Space.md, Space.xs),
            child: Text(title!, style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
          child: Column(children: rows),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Space.md, Space.xs, Space.md, 0),
            child: Text(footer!, style: context.text.bodySmall),
          ),
      ],
    );
  }
}

class GroupedTile extends StatelessWidget {
  const GroupedTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.chevron,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// In place of [icon], for marks that keep their own colour (a provider's
  /// logo).
  final Widget? leading;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  /// Defaults to showing a chevron when the row navigates.
  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = destructive ? c.danger : c.ink;
    final showChevron = chevron ?? (onTap != null && trailing == null);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          child: Row(
            children: [
              if (leading != null || icon != null) ...[
                SizedBox(width: 24, child: leading ?? Icon(icon, size: 22, color: destructive ? c.danger : c.forest)),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.bodyLarge?.copyWith(color: color)),
                    if (subtitle != null) ...[
                      const SizedBox(height: Space.hair),
                      Text(subtitle!, style: context.text.bodySmall),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: Space.sm),
                // Values sit against the trailing edge, as in iOS settings.
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge?.copyWith(color: c.inkMuted),
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: Space.sm), trailing!],
              if (showChevron) ...[
                const SizedBox(width: Space.xs),
                // Mirrors itself in Arabic.
                Icon(Icons.chevron_right_rounded, color: c.inkFaint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SheetAction<T> {
  const SheetAction({required this.value, required this.label, required this.icon, this.destructive = false});
  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// A short list of actions for one thing, behind a "more" button: an action
/// sheet on iOS, a bottom sheet elsewhere. Resolves to the chosen value.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required List<SheetAction<T>> actions,
  required String cancelLabel,
  String? title,
}) {
  final c = context.colors;
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final a in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: a.destructive,
              onPressed: () => Navigator.pop(context, a.value),
              child: Text(a.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: Text(cancelLabel),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
            ),
          for (final a in actions)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              leading: Icon(a.icon, color: a.destructive ? c.danger : c.forest),
              title: Text(a.label, style: a.destructive ? TextStyle(color: c.danger) : null),
              onTap: () => Navigator.pop(context, a.value),
            ),
          const SizedBox(height: Space.sm),
        ],
      ),
    ),
  );
}

/// A confirmation that looks native on each platform: a Cupertino alert on
/// iOS, a Material dialog elsewhere. Resolves true only on [confirmLabel].
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
  Widget? extra,
  ValueNotifier<bool>? enabled,
}) async {
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  final c = context.colors;
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) {
      Widget action(String label, bool value, {bool primary = false}) {
        if (ios) {
          return CupertinoDialogAction(
            isDestructiveAction: primary && destructive,
            isDefaultAction: primary && !destructive,
            onPressed: () => Navigator.pop(context, value),
            child: Text(label),
          );
        }
        if (!primary) return TextButton(onPressed: () => Navigator.pop(context, value), child: Text(label));
        return FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(context, value),
          child: Text(label),
        );
      }

      Widget confirm = action(confirmLabel, true, primary: true);
      if (enabled != null) {
        confirm = ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, on, _) => IgnorePointer(
            ignoring: !on,
            child: Opacity(opacity: on ? 1 : 0.4, child: action(confirmLabel, true, primary: true)),
          ),
        );
      }
      return AlertDialog.adaptive(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(body), ?extra],
        ),
        actions: [action(cancelLabel, false), confirm],
      );
    },
  );
  return ok ?? false;
}
