import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';

/// A shimmering placeholder in the shape of the content that is loading.
/// With reduced motion on, it holds still.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = Radii.sm});

  const Skeleton.line({super.key, this.width, this.height = 14}) : radius = Radii.xs;

  final double? width;
  final double? height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1.6 + t * 3.2, 0),
                end: Alignment(-0.6 + t * 3.2, 0),
                colors: [
                  c.surfaceMuted,
                  Color.alphaBlend(c.surface.withValues(alpha: 0.6), c.surfaceMuted),
                  c.surfaceMuted,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The skeleton of a property card, matching PropertyCard's proportions so
/// nothing jumps when the real card arrives.
class PropertyCardSkeleton extends StatelessWidget {
  const PropertyCardSkeleton({super.key, this.width});
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The card's own shape: a grey card, the photo's place, a white panel.
    return Container(
      width: width,
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.line(width: 150, height: 18),
                SizedBox(height: Space.xs),
                Skeleton.line(width: 110),
                SizedBox(height: Space.lg),
                Row(
                  children: [
                    Skeleton(width: 46, height: 30, radius: Radii.pill),
                    SizedBox(width: Space.iconGap),
                    Skeleton(width: 46, height: 30, radius: Radii.pill),
                    Spacer(),
                    Skeleton.line(width: 96, height: 22),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
