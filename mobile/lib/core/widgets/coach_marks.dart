import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import 'brand.dart';

/// Text for a tour card, read in the current language each time the card is
/// drawn, so switching language mid-tour switches the tour too.
typedef CoachText = String Function(AppLocalizations l);

/// One stop on a guided tour: the real control it points at, and what to
/// say about it. With no [target], a welcome card in the middle of the
/// screen.
class CoachStep {
  const CoachStep({required this.title, required this.body, this.target, this.circle = false});

  final GlobalKey? target;
  final CoachText title;
  final CoachText body;

  /// A round spotlight, for icons and tabs; otherwise a rounded rectangle.
  final bool circle;
}

/// How a tour ended.
enum CoachOutcome {
  /// The last card's button.
  finished,

  /// Skip, or the system back gesture.
  skipped,

  /// Taken off screen without an answer (a link opened another page): the
  /// tour has not been seen and is offered again.
  interrupted,
}

/// Walks through [steps] over the live screen: everything dims except the
/// control being explained, and a card says what it does. Steps whose
/// control is not on screen are left out. Starts at [start] (to pick up a
/// tour cut short) and reports each step reached through [onStep].
Future<CoachOutcome> showCoachMarks(
  BuildContext context,
  List<CoachStep> steps, {
  int start = 0,
  ValueChanged<int>? onStep,
}) async {
  final screen = Offset.zero & MediaQuery.sizeOf(context);
  // Only controls actually on screen: a tour never points into the void.
  final shown = steps.where((s) {
    final t = s.target;
    if (t == null) return true;
    final r = _rectOf(t);
    return r != null && screen.contains(r.center) && r.width > 0 && r.height > 0;
  }).toList();
  if (shown.isEmpty) return CoachOutcome.skipped;
  // Answered by the card's buttons, or by the overlay going away unanswered.
  final ended = Completer<CoachOutcome>();
  final route = PageRouteBuilder<CoachOutcome>(
    opaque: false,
    transitionDuration: Motion.of(context, Motion.normal),
    reverseTransitionDuration: Motion.of(context, Motion.fast),
    pageBuilder: (_, _, _) => _CoachOverlay(
      steps: shown,
      start: start.clamp(0, shown.length - 1),
      onStep: onStep,
      onGone: () {
        if (!ended.isCompleted) ended.complete(CoachOutcome.interrupted);
      },
    ),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );
  unawaited(
    Navigator.of(context, rootNavigator: true).push<CoachOutcome>(route).then((outcome) {
      // The card and the back gesture always answer; no answer means the
      // page under the tour was replaced (a link, a notification).
      if (!ended.isCompleted) ended.complete(outcome ?? CoachOutcome.interrupted);
    }),
  );
  return ended.future;
}

Rect? _rectOf(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null || !ctx.mounted) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _CoachOverlay extends StatefulWidget {
  const _CoachOverlay({required this.steps, required this.start, required this.onGone, this.onStep});
  final List<CoachStep> steps;
  final int start;
  final ValueChanged<int>? onStep;

  /// The overlay left the screen, answered or not.
  final VoidCallback onGone;

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> with SingleTickerProviderStateMixin {
  late int _i = widget.start;

  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    widget.onStep?.call(_i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPulse());
  }

  /// Two soft pulses as each step appears, then stillness; none at all with
  /// reduced motion.
  void _startPulse() {
    if (!mounted || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
    _pulse.reset();
    unawaited(_pulse.repeat(count: 2));
  }

  @override
  void dispose() {
    _pulse.dispose();
    widget.onGone();
    super.dispose();
  }

  void _go(int to) {
    if (to >= widget.steps.length) {
      Navigator.of(context).pop(CoachOutcome.finished);
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    setState(() => _i = to.clamp(0, widget.steps.length - 1));
    widget.onStep?.call(_i);
    _startPulse();
  }

  /// After a rotation, a resize or a scroll the control has moved: the
  /// screen lays out after this card is built, so look again once it has.
  void _followTarget(Rect? used) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final t = widget.steps[_i].target;
      final now = t == null ? null : _rectOf(t);
      if (now == null || used == null) return;
      final moved =
          (now.topLeft - used.topLeft).distance > 0.5 ||
          (now.width - used.width).abs() > 0.5 ||
          (now.height - used.height).abs() > 0.5;
      if (moved) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    final welcome = step.target == null;
    final measured = step.target == null ? null : _rectOf(step.target!);
    _followTarget(measured);
    final target = (measured ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0)).inflate(6);
    final hole = welcome
        ? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0)
        : (step.circle ? Rect.fromCircle(center: target.center, radius: target.longestSide / 2) : target);
    final duration = Motion.of(context, Motion.normal);

    final card = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: step.title(l),
      child: Material(
        // In the dark, a raised surface with an edge, so the card stands off
        // the dimmed screen as clearly as it does in the light.
        color: dark ? c.surfaceRaised : c.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: dark ? BorderSide(color: c.border) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (welcome) ...[const BrandMark(size: 44), const SizedBox(height: Space.sm)],
              // Same height with or without Skip, so the card does not jump.
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.tourStepOf(_i + 1, widget.steps.length),
                        style: context.type.pill.copyWith(color: c.emerald),
                      ),
                    ),
                    if (!last)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(CoachOutcome.skipped),
                        child: Text(l.tourSkip),
                      ),
                  ],
                ),
              ),
              // The words scroll when there is no room for them all (large
              // text, a phone on its side); the buttons always show.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.only(end: Space.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(liveRegion: true, child: Text(step.title(l), style: context.text.titleMedium)),
                      const SizedBox(height: Space.xxs),
                      Text(step.body(l), style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  if (_i > 0) TextButton(onPressed: () => _go(_i - 1), child: Text(l.actionBack)),
                  const Spacer(),
                  FilledButton(onPressed: () => _go(_i + 1), child: Text(last ? l.tourDone : l.actionNext)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      // The system back gesture skips the tour, like Skip.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(CoachOutcome.skipped);
      },
      child: Stack(
        children: [
          // Holds every touch: the tour is read, not tapped through.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: hole),
                duration: duration,
                curve: Motion.emphasized,
                builder: (context, r, _) => CustomPaint(
                  painter: _SpotlightPainter(hole: r ?? hole, circle: step.circle, pulse: welcome ? null : _pulse),
                ),
              ),
            ),
          ),
          // The card measures itself and stays inside the safe area: under
          // the control, or over it, or beside it on a wide screen.
          Positioned.fill(
            child: TweenAnimationBuilder<Rect?>(
              tween: RectTween(end: hole),
              duration: duration,
              curve: Motion.emphasized,
              builder: (context, r, child) => CustomSingleChildLayout(
                delegate: _CardLayout(
                  hole: r ?? hole,
                  safe: safe,
                  centred: welcome,
                  rtl: Directionality.of(context) == TextDirection.rtl,
                ),
                child: child,
              ),
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                child: KeyedSubtree(key: ValueKey(_i), child: card),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Places the tour card: never off screen, preferably clear of the control.
class _CardLayout extends SingleChildLayoutDelegate {
  _CardLayout({required this.hole, required this.safe, required this.centred, required this.rtl});

  final Rect hole;
  final EdgeInsets safe;
  final bool centred;
  final bool rtl;

  static const double _margin = Space.gutter;
  static const double _gap = Space.md;
  static const double _maxWidth = 400;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(0.0, math.min(constraints.maxWidth - safe.horizontal - 2 * _margin, _maxWidth));
    final height = constraints.maxHeight - safe.vertical - 2 * _margin;
    return BoxConstraints(maxWidth: width, minWidth: width, maxHeight: math.max(0, height));
  }

  @override
  Offset getPositionForChild(Size size, Size card) {
    final top = safe.top + _margin;
    final bottom = size.height - safe.bottom - _margin;
    final left = safe.left + _margin;
    final right = size.width - safe.right - _margin;
    if (centred) {
      return Offset(left + (right - left - card.width) / 2, top + (bottom - top - card.height) / 2);
    }
    final x = (hole.center.dx - card.width / 2).clamp(left, math.max(left, right - card.width)).toDouble();
    final below = bottom - (hole.bottom + _gap);
    final above = (hole.top - _gap) - top;
    if (card.height <= below && (below >= above || card.height > above)) {
      return Offset(x, hole.bottom + _gap);
    }
    if (card.height <= above) return Offset(x, hole.top - _gap - card.height);
    // No room above or below (a tall control, landscape): beside it when
    // the screen is wide enough, otherwise at the roomier end.
    final besideStart = hole.left - _gap - left;
    final besideEnd = right - (hole.right + _gap);
    if (math.max(besideStart, besideEnd) >= card.width) {
      final toEnd = besideEnd >= card.width && (!rtl || besideStart < card.width);
      final bx = toEnd ? hole.right + _gap : hole.left - _gap - card.width;
      final by = (hole.center.dy - card.height / 2).clamp(top, math.max(top, bottom - card.height)).toDouble();
      return Offset(bx, by);
    }
    final y = below >= above ? bottom - card.height : top;
    return Offset(x, y.clamp(top, math.max(top, bottom - card.height)).toDouble());
  }

  @override
  bool shouldRelayout(_CardLayout old) =>
      old.hole != hole || old.safe != safe || old.centred != centred || old.rtl != rtl;
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.circle, this.pulse}) : super(repaint: pulse);
  final Rect hole;
  final bool circle;

  /// A ring that swells and fades around the control, drawing the eye.
  final Animation<double>? pulse;

  Path _shape(Rect r) =>
      circle ? (Path()..addOval(r)) : (Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(Radii.lg))));

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), _shape(hole));
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.62));
    if (hole.isEmpty) return;
    canvas.drawPath(
      _shape(hole),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    final t = pulse?.value ?? 0;
    if (pulse != null && pulse!.isAnimating) {
      canvas.drawPath(
        _shape(hole.inflate(10 * t)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.55 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.circle != circle;
}
