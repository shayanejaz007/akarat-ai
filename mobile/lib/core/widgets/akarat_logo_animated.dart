import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// The Akarat.ai logo building itself: a gold glow, the frame lines drawn
/// on, the towers rising, the name written out, the dot, a last pulse of
/// light. The splash kit's coded animation (same geometry and timeline as the
/// website's), used when the intro clip cannot play; with [animate] false, or
/// with reduced motion, the finished logo.
class AkaratLogoAnimated extends StatefulWidget {
  const AkaratLogoAnimated({super.key, this.size = 300, this.animate = true, this.onComplete});

  /// The side of the square the logo is drawn in.
  final double size;
  final bool animate;

  /// Called once the logo has finished building (at once when it is still).
  final VoidCallback? onComplete;

  /// How long the build takes.
  static const duration = Duration(milliseconds: 3750);

  @override
  State<AkaratLogoAnimated> createState() => _AkaratLogoAnimatedState();
}

class _AkaratLogoAnimatedState extends State<AkaratLogoAnimated> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: AkaratLogoAnimated.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final still = !widget.animate || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete?.call();
      });
    } else {
      _c.forward().whenCompleteOrCancel(() {
        if (mounted && _c.isCompleted) widget.onComplete?.call();
      });
    }
  }

  @override
  void didUpdateWidget(AkaratLogoAnimated old) {
    super.didUpdateWidget(old);
    // Asked to build after all (or to stop): start over accordingly.
    if (widget.animate != old.animate) {
      _started = false;
      _c.reset();
      didChangeDependencies();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Akarat.ai',
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _LogoPainter(_c)),
    ),
  );
}

/// The logo in a 1080-unit square, as the kit's SVG draws it.
class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static final _frames = [
    'M310 725 V430 L376 398',
    'M386 442 V328 L456 292',
    'M624 292 L694 328 V470',
    'M704 398 L770 430 V725',
  ].map(_Stroke.new).toList();
  static final _letters = [
    'M92 872 L154 790 L216 872',
    'M264 788 V872 M336 790 L272 832 L342 872',
    'M366 872 L428 790 L490 872',
    'M514 872 V790 H572 Q602 790 602 812 Q602 834 572 834 H522 M566 834 L604 872',
    'M614 872 L676 790 L738 872',
    'M728 790 H836 M782 790 V872',
    'M858 872 L916 790 L974 872',
    'M990 788 V872',
  ].map(_Stroke.new).toList();
  static final _towerGold = _svgPath('M473 212 L602 116 V612 L527 543 V725 H473Z');
  static final _towerNotch = _svgPath('M532 590 L602 657 V725 H532Z');
  static final _towerLeft = _svgPath('M347 470 L443 402 V725 H347Z');
  static final _towerRight = _svgPath('M632 386 L656 398 V408 L646 410 V442 L733 516 V725 H632Z');

  static final _gold = ui.Gradient.linear(
    const Offset(300, 100),
    const Offset(820, 900),
    const [Color(0xFFF8DA8A), Color(0xFFE0AE45), Color(0xFFC38B2A), Color(0xFF9C6A1C)],
    const [0, 0.42, 0.75, 1],
  );
  static final _steel = ui.Gradient.linear(
    const Offset(340, 380),
    const Offset(740, 740),
    const [Color(0xFF7A7A7D), Color(0xFF58585B), Color(0xFF38383A)],
    const [0, 0.5, 1],
  );
  static final _ambient = ui.Gradient.radial(const Offset(540, 520), 520, const [Color(0x38D9A43A), Color(0x00D9A43A)]);

  /// The closing pulse: the same light, gone by its own edge (the kit reuses
  /// the wider glow here, which leaves a visible rim).
  static final _pulse = ui.Gradient.radial(const Offset(540, 520), 420, const [Color(0x38D9A43A), Color(0x00D9A43A)]);

  static const _ease = Cubic(0.65, 0, 0.35, 1);
  static const _out = Cubic(0.16, 1, 0.3, 1);
  static const _pop = Cubic(0.34, 1.56, 0.64, 1);

  /// Progress of a part that starts at [delay] ms and lasts [length] ms.
  double _at(double ms, double delay, double length, Curve curve) =>
      curve.transform(((ms - delay) / length).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final ms = t.value * AkaratLogoAnimated.duration.inMilliseconds;
    canvas
      ..save()
      ..scale(size.width / 1080, size.height / 1080);

    // The glow behind it, and a last pulse once it is built.
    final ambient = _at(ms, 0, 1600, Curves.easeOutQuad);
    if (ambient > 0) {
      canvas
        ..save()
        ..translate(540, 520)
        ..scale(0.8 + 0.2 * ambient)
        ..translate(-540, -520)
        ..drawCircle(
          const Offset(540, 520),
          520,
          Paint()
            ..shader = _ambient
            ..color = Color.fromRGBO(0, 0, 0, ambient),
        )
        ..restore();
    }
    final glow = ms < 3050 ? _at(ms, 2550, 500, Curves.easeInOut) : 1 - _at(ms, 3050, 700, Curves.easeInOut);
    if (glow > 0) {
      canvas.drawCircle(
        const Offset(540, 520),
        420,
        Paint()
          ..shader = _pulse
          ..color = Color.fromRGBO(0, 0, 0, glow),
      );
    }

    // The frame lines, drawn on one after another.
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.square
      ..shader = _gold;
    for (var i = 0; i < _frames.length; i++) {
      _frames[i].draw(canvas, frame, _at(ms, 150 + i * 120.0, 750, _ease));
    }

    // The towers rise from behind the ground line.
    void rise(Path tower, ui.Gradient fill, double delay, double from) {
      final p = _at(ms, delay, 900, _out);
      if (p <= 0) return;
      canvas
        ..save()
        ..clipRect(const Rect.fromLTWH(0, 0, 1080, 725))
        ..translate(0, from * (1 - p))
        ..drawPath(tower, Paint()..shader = fill)
        ..restore();
    }

    rise(_towerLeft, _steel, 850, 380);
    rise(_towerRight, _steel, 980, 380);
    rise(_towerGold, _gold, 450, 560);
    rise(_towerNotch, _steel, 1100, 380);

    // The name, written letter by letter, then its dot.
    final letter = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..shader = _gold;
    for (var i = 0; i < _letters.length; i++) {
      _letters[i].draw(canvas, letter, _at(ms, 1350 + i * 70.0, 550, _ease));
    }
    final dot = _at(ms, 1800, 450, _pop);
    if (dot > 0) {
      canvas
        ..save()
        ..translate(847, 863)
        ..scale(math.max(0, dot))
        ..drawCircle(Offset.zero, 10, Paint()..shader = _gold)
        ..restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t;
}

/// A stroke that can be drawn part of the way along, as an SVG dash offset
/// draws it: across its sub-paths in order.
class _Stroke {
  _Stroke(String d) : path = _svgPath(d) {
    metrics = path.computeMetrics().toList();
    length = metrics.fold(0, (sum, m) => sum + m.length);
  }

  final Path path;
  late final List<ui.PathMetric> metrics;
  late final double length;

  void draw(Canvas canvas, Paint paint, double t) {
    if (t <= 0) return;
    if (t >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    var left = length * t;
    final part = Path();
    for (final m in metrics) {
      if (left <= 0) break;
      part.addPath(m.extractPath(0, math.min(left, m.length)), Offset.zero);
      left -= m.length;
    }
    canvas.drawPath(part, paint);
  }
}

/// The absolute M, L, H, V, Q and Z commands the logo's paths use.
Path _svgPath(String d) {
  final tokens = RegExp(r'[MLHVQZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  var cmd = 'M';
  double x = 0;
  double y = 0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp('[MLHVQZ]').hasMatch(tokens[i])) {
      cmd = tokens[i++];
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x, y);
        cmd = 'L';
      case 'L':
        x = next();
        y = next();
        path.lineTo(x, y);
      case 'H':
        x = next();
        path.lineTo(x, y);
      case 'V':
        y = next();
        path.lineTo(x, y);
      case 'Q':
        final cx = next();
        final cy = next();
        x = next();
        y = next();
        path.quadraticBezierTo(cx, cy, x, y);
    }
  }
  return path;
}
