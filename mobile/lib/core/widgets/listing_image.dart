import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';
import 'skeleton.dart';

/// A listing photograph: disk-cached, decoded at the size it is shown rather
/// than at the camera's resolution, and with a calm placeholder for the
/// listings that have no photo at all.
class ListingImage extends StatelessWidget {
  const ListingImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.greyscale = false,
    this.semanticLabel,
    this.decodeWidth,
    this.decodeHeight,
  });

  final String? url;
  final BoxFit fit;

  /// Sold and rented listings lose their colour, as on the website.
  final bool greyscale;
  final String? semanticLabel;

  /// Logical width the image is drawn at; decoded at device-pixel size.
  final double? decodeWidth;

  /// Logical height of the frame, for [BoxFit.cover]: a photo wider than its
  /// frame is cropped at the sides and scaled to the frame's height, so it
  /// needs more pixels across than the frame is wide.
  final double? decodeHeight;

  /// The widest photos decoded with full sharpness when cropped to fill:
  /// panoramas up to 1.6 : 1 (wider ones soften slightly).
  static const _widest = 1.6;

  static const _buckets = [256, 512, 768, 1080, 1440, 2048];

  /// Decode sizes snap up to a few widths, so a photo shown at slightly
  /// different sizes (a card, then the listing's gallery) shares one decoded
  /// copy instead of being decoded again on arrival. Tiny decodes (the
  /// viewer's soft backdrop) stay exact.
  static int? _bucket(int? px) {
    if (px == null || px < 200) return px;
    for (final b in _buckets) {
      if (px <= b) return b;
    }
    return px;
  }

  /// The sharpest copy of this photo already decoded in memory (a card's,
  /// say), shown while this size is decoded, so a photo that was on screen a
  /// moment ago never flashes blank.
  static ImageProvider? _decodedCopy(String url, ImageConfiguration config) {
    final cache = PaintingBinding.instance.imageCache;
    for (final b in _buckets.reversed) {
      // Built exactly as CachedNetworkImage keys its memory cache.
      final provider = ResizeImage(CachedNetworkImageProvider(url), width: b);
      Object? key;
      // Synchronous for a network provider: the key is ready at once.
      provider.obtainKey(config).then((k) => key = k);
      if (key == null) continue;
      final status = cache.statusForKey(key!);
      // Not a copy still on its way (often this very size): it would draw
      // nothing until it lands, where the skeleton at least shows a photo
      // is coming.
      if (!status.pending && (status.keepAlive || status.live)) return provider;
    }
    return null;
  }

  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return const _NoPhoto();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = decodeWidth;
    final h = decodeHeight;
    final logical = w == null ? null : (fit == BoxFit.cover && h != null ? math.max(w, h * _widest) : w);
    final cacheWidth = _bucket(logical == null ? null : (logical * dpr).round());
    final config = createLocalImageConfiguration(context);
    Widget img = CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: Motion.of(context, Motion.normal),
      placeholder: (_, _) {
        final copy = _decodedCopy(u, config);
        return copy == null ? const Skeleton(radius: 0) : Image(image: copy, fit: fit, gaplessPlayback: true);
      },
      errorWidget: (_, _, _) => const _NoPhoto(),
    );
    if (greyscale) {
      img = ColorFiltered(
        colorFilter: _grey,
        child: Opacity(opacity: 0.88, child: img),
      );
    }
    return Semantics(label: semanticLabel, image: true, child: img);
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.surfaceMuted, Color.alphaBlend(c.sand.withValues(alpha: 0.35), c.surfaceMuted)],
        ),
      ),
      child: Center(child: Icon(Icons.home_work_outlined, size: 34, color: c.inkFaint)),
    );
  }
}
