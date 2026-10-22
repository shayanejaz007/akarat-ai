import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// Fades and lifts its child into place the first time it appears. Items in
/// a list pass their [index] for a short stagger; an [id] makes the reveal
/// happen once per session, so scrolling back up does not replay it. With
/// reduced motion the child is simply there.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.id, this.distance = 18});

  final Widget child;
  final int index;
  final String? id;
  final double distance;

  static final _seen = <String>{};

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    final id = widget.id;
    if (id != null && Reveal._seen.contains(id)) {
      _c.value = 1;
      return;
    }
    if (id != null) {
      if (Reveal._seen.length > 2000) Reveal._seen.clear();
      Reveal._seen.add(id);
    }
    // Only the first few items in a list wait their turn; the rest of a
    // long list should not lag behind the scroll.
    final wait = Duration(milliseconds: math.min(widget.index, 6) * 50);
    _delay = Timer(wait, () {
      if (mounted) unawaited(_c.forward());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _delay?.cancel();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Motion.standard.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * widget.distance), child: child),
        );
      },
    );
  }
}

/// A short, quiet confirmation over the screen: a check that draws itself
/// and a line of text. It never blocks a touch and is gone in a moment.
void showSuccess(BuildContext context, String message, {IconData? icon}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  unawaited(HapticFeedback.mediumImpact());
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SuccessToast(message: message, icon: icon, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _SuccessToast extends StatefulWidget {
  const _SuccessToast({required this.message, required this.onDone, this.icon});
  final String message;
  final IconData? icon;
  final VoidCallback onDone;

  @override
  State<_SuccessToast> createState() => _SuccessToastState();
}

class _SuccessToastState extends State<_SuccessToast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void initState() {
    super.initState();
    unawaited(_c.forward().whenComplete(widget.onDone));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            // In 0–18%, hold, out over the last 18%.
            final inT = Curves.easeOutBack.transform((v / 0.18).clamp(0.0, 1.0));
            final outT = ((v - 0.82) / 0.18).clamp(0.0, 1.0);
            final draw = still ? 1.0 : Curves.easeOutCubic.transform(((v - 0.08) / 0.3).clamp(0.0, 1.0));
            final opacity = (still ? 1.0 : inT.clamp(0.0, 1.0)) * (1 - outT);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: still ? 1 : 0.85 + 0.15 * inT,
                child: Semantics(
                  liveRegion: true,
                  label: widget.message,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: Radii.card,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: widget.icon != null
                              ? Icon(widget.icon, size: 40, color: c.emerald)
                              : CustomPaint(
                                  painter: _CheckPainter(progress: draw, colour: c.emerald),
                                ),
                        ),
                        const SizedBox(height: Space.sm),
                        Text(widget.message, textAlign: TextAlign.center, style: context.text.titleSmall),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A ring, then a tick drawn stroke by stroke.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.colour});
  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = size.width / 2 - 2;
    final centre = size.center(Offset.zero);
    final ring = (progress / 0.6).clamp(0.0, 1.0);
    canvas.drawCircle(centre, r, Paint()..color = colour.withValues(alpha: 0.12 * ring));
    canvas.drawArc(Rect.fromCircle(center: centre, radius: r), -math.pi / 2, 2 * math.pi * ring, false, stroke);
    final tick = ((progress - 0.45) / 0.55).clamp(0.0, 1.0);
    if (tick <= 0) return;
    final a = Offset(size.width * 0.3, size.height * 0.52);
    final b = Offset(size.width * 0.44, size.height * 0.66);
    final d = Offset(size.width * 0.71, size.height * 0.38);
    final first = (Offset(b.dx - a.dx, b.dy - a.dy)).distance;
    final second = (Offset(d.dx - b.dx, d.dy - b.dy)).distance;
    final len = (first + second) * tick;
    final path = Path()..moveTo(a.dx, a.dy);
    if (len <= first) {
      path.lineTo(a.dx + (b.dx - a.dx) * len / first, a.dy + (b.dy - a.dy) * len / first);
    } else {
      final rest = (len - first) / second;
      path
        ..lineTo(b.dx, b.dy)
        ..lineTo(b.dx + (d.dx - b.dx) * rest, b.dy + (d.dy - b.dy) * rest);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress || old.colour != colour;
}
