import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:google_maps_flutter/google_maps_flutter.dart' show BitmapDescriptor;
import 'package:material_ui/material_ui.dart';

/// A pin drawn as an image for Google's native map, with the point on the
/// image that sits on the map location.
class PinImage {
  const PinImage({required this.icon, required this.anchor, required this.size});
  final BitmapDescriptor icon;

  /// Fractions of the image: (0.5, 1) is the middle of the bottom edge.
  final Offset anchor;

  /// Logical size, for tests and layout checks.
  final Size size;
}

/// The map's pins as images: the same rounded price label with a pointer,
/// numbered bubble and location pin that the key-free map draws in Flutter.
/// Native maps take images, not widgets. Each distinct pin is drawn once,
/// at the screen's pixel density, and kept.
class MapPinImages {
  MapPinImages({required this.devicePixelRatio, required this.textStyle, required this.textScale});

  final double devicePixelRatio;

  /// The theme's label style, with the app's fonts and Arabic fallback.
  final TextStyle textStyle;

  /// Text size factor, capped like the Flutter pins (1.0 to 1.2).
  final double textScale;

  final _cache = <String, Future<PinImage>>{};

  /// Room around a pin for its shadow.
  static const double _margin = 4;
  static const double _pointer = 7;

  /// A price label: [background] fill, white edge, a pointer underneath.
  Future<PinImage> price(String label, {required Color background, required Color foreground, required bool selected}) {
    final key = 'p|$label|${background.toARGB32()}|${foreground.toARGB32()}|$selected';
    return _cache[key] ??= _draw(() {
      final text = _text(label, foreground, selected ? 14 : 13);
      final border = selected ? 2.5 : 1.5;
      final bubbleH = (selected ? 34.0 : 30.0) * textScale;
      final bubbleW = math.max(text.width + 20 + 2 * border, 44.0);
      final size = Size(bubbleW + 2 * _margin, bubbleH + _pointer + 2 * _margin);
      return (
        size,
        (Canvas c) {
          final bubble = RRect.fromRectAndRadius(
            Rect.fromLTWH(_margin, _margin, bubbleW, bubbleH),
            Radius.circular(bubbleH / 2),
          );
          _shadow(c, bubble, selected ? 0.35 : 0.22, selected ? 6 : 3);
          c.drawRRect(bubble, Paint()..color = Colors.white);
          c.drawRRect(bubble.deflate(border), Paint()..color = background);
          final mid = _margin + bubbleW / 2;
          final top = _margin + bubbleH - border;
          c.drawPath(
            Path()
              ..moveTo(mid - 6, top)
              ..lineTo(mid + 6, top)
              ..lineTo(mid, _margin + bubbleH + _pointer)
              ..close(),
            Paint()..color = background,
          );
          text.paint(c, Offset(mid - text.width / 2, _margin + (bubbleH - text.height) / 2));
          text.dispose();
        },
        // The pointer's tip.
        Offset(0.5, (_margin + bubbleH + _pointer) / size.height),
      );
    });
  }

  /// A numbered bubble for pins too close to tell apart; [ring] marks a
  /// bubble that mixes sale and rent.
  Future<PinImage> cluster(int count, {required Color background, required Color foreground, Color? ring}) {
    final key = 'c|$count|${background.toARGB32()}|${foreground.toARGB32()}|${ring?.toARGB32()}';
    return _cache[key] ??= _draw(() {
      final diameter = (36 + math.min(count, 40) * 0.5) * textScale;
      final size = Size.square(diameter + 2 * _margin);
      return (
        size,
        (Canvas c) {
          final centre = Offset(size.width / 2, size.height / 2);
          final circle = RRect.fromRectAndRadius(
            Rect.fromCircle(center: centre, radius: diameter / 2),
            Radius.circular(diameter / 2),
          );
          _shadow(c, circle, 0.25, 3);
          c.drawCircle(centre, diameter / 2, Paint()..color = ring ?? Colors.white);
          c.drawCircle(centre, diameter / 2 - (ring == null ? 2 : 3), Paint()..color = background);
          final text = _text('$count', foreground, 15);
          text.paint(c, centre - Offset(text.width / 2, text.height / 2));
          text.dispose();
        },
        const Offset(0.5, 0.5),
      );
    });
  }

  /// The single location pin of a listing's own map and the pin picker.
  Future<PinImage> place(Color colour) {
    final key = 'l|${colour.toARGB32()}';
    return _cache[key] ??= _draw(() {
      const glyph = Icons.location_on_rounded;
      const side = 44.0;
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(glyph.codePoint),
          style: TextStyle(
            fontFamily: glyph.fontFamily,
            package: glyph.fontPackage,
            fontSize: side,
            color: colour,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 3, offset: const Offset(0, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const size = Size.square(side + 2 * _margin);
      return (
        size,
        (Canvas c) {
          painter.paint(c, const Offset(_margin, _margin));
          painter.dispose();
        },
        // The glyph's tip sits a little above its box's bottom edge.
        const Offset(0.5, (_margin + side * 0.92) / (side + 2 * _margin)),
      );
    });
  }

  TextPainter _text(String text, Color colour, double size) => TextPainter(
    text: TextSpan(
      text: text,
      style: textStyle.copyWith(color: colour, fontSize: size * textScale, fontWeight: FontWeight.w700, height: 1.1),
    ),
    // Prices read left to right in both languages, as on the Flutter pins.
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  static void _shadow(Canvas c, RRect shape, double alpha, double blur) {
    c.drawRRect(
      shape.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
  }

  /// Lays the pin out, paints it at device pixels and wraps it for the map.
  Future<PinImage> _draw((Size, void Function(Canvas), Offset) Function() layout) async {
    final (size, paint, anchor) = layout();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * devicePixelRatio).ceil(),
      (size.height * devicePixelRatio).ceil(),
    );
    picture.dispose();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return PinImage(
      icon: BitmapDescriptor.bytes(png!.buffer.asUint8List(), imagePixelRatio: devicePixelRatio),
      anchor: anchor,
      size: size,
    );
  }
}
