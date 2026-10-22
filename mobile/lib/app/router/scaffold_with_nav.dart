import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/networking/connectivity.dart';
import '../../features/tour/tour.dart';
import '../../shared/services/supabase_providers.dart';
import '../localization/l10n.dart';
import '../theme/tokens.dart';
import 'routes.dart';

/// The five-tab shell. Each tab keeps its own navigation stack and scroll
/// position (IndexedStack under StatefulShellRoute); tapping the active tab
/// again returns it to its first screen.
class ScaffoldWithNav extends ConsumerWidget {
  const ScaffoldWithNav({super.key, required this.shell});
  final StatefulNavigationShell shell;

  /// Height of the floating bar itself.
  static const barHeight = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final l = context.l10n;
    final t = ref.watch(tourTargetsProvider);
    final mq = MediaQuery.of(context);
    // With the keyboard up the bar steps aside, as on iOS.
    final keyboard = mq.viewInsets.bottom > 0;
    final lift = math.max(mq.padding.bottom, Space.sm);
    // What the floating bar covers; screens keep their content clear of it.
    final reserve = keyboard ? mq.padding.bottom : barHeight + lift + Space.xs;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              AnimatedSize(
                duration: Motion.of(context, Motion.normal),
                curve: Motion.standard,
                child: offline ? _OfflineBanner(text: l.offlineBanner) : const SizedBox(width: double.infinity),
              ),
              Expanded(
                child: MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(bottom: reserve),
                    viewPadding: mq.viewPadding.copyWith(bottom: reserve),
                  ),
                  child: shell,
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: lift,
            child: AnimatedSlide(
              offset: keyboard ? const Offset(0, 2) : Offset.zero,
              duration: Motion.of(context, Motion.normal),
              curve: Motion.standard,
              child: IgnorePointer(
                ignoring: keyboard,
                child: AkaratNavBar(
                  index: shell.currentIndex,
                  signedIn: signedIn,
                  tabKeys: [null, t.navExplore, t.navAi, t.navSaved, t.navProfile],
                  onSelect: (i) {
                    unawaited(HapticFeedback.selectionClick());
                    shell.goBranch(i, initialLocation: i == shell.currentIndex);
                  },
                  onSignIn: () => context.push(Routes.signIn),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: c.ink,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, size: 16, color: c.background),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(text, style: context.text.labelMedium?.copyWith(color: c.background)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating tab bar: a white pill over the content. The current tab is
/// a dark green pill carrying its name; the others are icons. Signed out, the
/// last place is a green "Log in" button rather than an empty profile.
class AkaratNavBar extends StatelessWidget {
  const AkaratNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.signedIn = true,
    this.onSignIn,
    this.tabKeys = const [],
  });
  final int index;
  final ValueChanged<int> onSelect;
  final bool signedIn;
  final VoidCallback? onSignIn;

  /// Anchors for the guided tour, by tab.
  final List<Key?> tabKeys;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      (Icons.home_outlined, Icons.home_rounded, l.tabHome),
      (Icons.explore_outlined, Icons.explore_rounded, l.tabExplore),
      (Icons.auto_awesome_outlined, Icons.auto_awesome, l.tabAiSearch),
      (Icons.favorite_border_rounded, Icons.favorite_rounded, l.tabSaved),
      (Icons.person_outline_rounded, Icons.person_rounded, l.tabProfile),
    ];
    return MediaQuery(
      // Labels grow a little with Dynamic Type, not enough to break the bar.
      data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15)),
      child: Center(
        heightFactor: 1,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          // A little closer to the edges on small phones, for the chosen name.
          margin: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 380 ? Space.xs : Space.sm),
          height: ScaffoldWithNav.barHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ScaffoldWithNav.barHeight / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // The reference's frosted pane, without a live blur: blurring what
          // scrolls beneath costs a frame-time hit on every scroll frame.
          child: _Pane(
            radius: ScaffoldWithNav.barHeight / 2,
            tint: (dark ? c.surfaceRaised : c.surface).withValues(alpha: 0.95),
            border: c.border.withValues(alpha: dark ? 1 : 0.6),
            child: LayoutBuilder(
              builder: (context, box) {
                // The chosen tab shows its whole name when it fits beside the
                // others, or stays an icon in its dark pill (the name is still
                // read out): never a word cut short.
                final style = context.text.labelLarge;
                final scaler = MediaQuery.textScalerOf(context);
                final dir = Directionality.of(context);
                double textWidth(String s) {
                  final tp = TextPainter(
                    text: TextSpan(text: s, style: style),
                    textDirection: dir,
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout();
                  final w = tp.width;
                  tp.dispose();
                  return w;
                }

                final login = signedIn ? 0.0 : _LoginPill.widthFor(textWidth(l.navLogIn));
                final room = box.maxWidth - (signedIn ? 4 : 3) * _NavItem.iconWidth - login;
                final named = index < items.length && _NavItem.widthFor(textWidth(items[index].$3)) <= room;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      if (i == 4 && !signedIn)
                        _LoginPill(key: i < tabKeys.length ? tabKeys[i] : null, label: l.navLogIn, onTap: onSignIn)
                      else
                        _NavItem(
                          key: i < tabKeys.length ? tabKeys[i] : null,
                          icon: items[i].$1,
                          activeIcon: items[i].$2,
                          label: items[i].$3,
                          selected: index == i,
                          named: named,
                          onTap: () => onSelect(i),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's rounded, nearly opaque pane.
class _Pane extends StatelessWidget {
  const _Pane({required this.radius, required this.tint, required this.border, required this.child});
  final double radius;
  final Color tint;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.named = true,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Chosen, with its name beside the icon (when there is room for it).
  final bool named;

  static const double iconWidth = 44;
  static const double _padding = Space.sm;
  static const double _icon = 23;
  static const double _gap = 6;

  /// Width of the chosen pill with a name [text] wide.
  static double widthFor(double text) => 2 * _padding + _icon + _gap + text + 1;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = Motion.of(context, Motion.normal);
    final pill = Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: d,
          curve: Motion.emphasized,
          height: 48,
          constraints: const BoxConstraints(minWidth: iconWidth),
          padding: EdgeInsets.symmetric(horizontal: selected ? _padding : 0),
          decoration: BoxDecoration(
            color: selected ? c.forest : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, size: _icon, color: selected ? c.onForest : c.ink),
              // The name slides out of the pill when it is chosen.
              Flexible(
                child: AnimatedSize(
                  duration: d,
                  curve: Motion.emphasized,
                  child: selected && named
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(start: _gap),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelLarge?.copyWith(color: c.onForest),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return selected ? Flexible(child: pill) : SizedBox(width: iconWidth, child: pill);
  }
}

/// Signed out: the profile's place, as a green call to sign in.
class _LoginPill extends StatelessWidget {
  const _LoginPill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  /// Width with a label [text] wide.
  static double widthFor(double text) => 2 * Space.sm + 18 + 6 + text + 1;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Sized to its label; the chosen tab's pill gives way, never this.
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            decoration: BoxDecoration(
              color: c.emerald,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: c.emerald.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.login_rounded, size: 18, color: Colors.white),
                const SizedBox(width: Space.iconGap),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(color: Colors.white),
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

/// The five tab stacks, kept alive like an IndexedStack, with a brief
/// cross-fade when switching (none when motion is reduced). Hidden tabs do
/// not tick, take touches or take part in hero flights.
class FadingBranches extends StatefulWidget {
  const FadingBranches({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<FadingBranches> createState() => _FadingBranchesState();
}

class _FadingBranchesState extends State<FadingBranches> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: Motion.fast, value: 1);
  int? _leaving;

  @override
  void didUpdateWidget(FadingBranches old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _leaving = null;
      _fade.value = 1;
      return;
    }
    _leaving = old.index;
    unawaited(
      _fade.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _leaving = null);
      }),
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Widget _layer(int i) {
    final current = i == widget.index;
    return Offstage(
      // Keyed, so a tab keeps its state when the order below changes.
      key: ValueKey(i),
      offstage: !current && i != _leaving,
      child: TickerMode(
        enabled: current,
        child: HeroMode(
          enabled: current,
          child: IgnorePointer(
            ignoring: !current,
            // Only the incoming tab fades, over the outgoing one held still:
            // one translucent layer per frame instead of two.
            child: FadeTransition(opacity: current ? _fade : kAlwaysCompleteAnimation, child: widget.children[i]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < n; i++)
          if (i != widget.index && i != _leaving) _layer(i),
        if (_leaving != null && _leaving != widget.index) _layer(_leaving!),
        // The chosen tab paints on top.
        _layer(widget.index),
      ],
    );
  }
}
