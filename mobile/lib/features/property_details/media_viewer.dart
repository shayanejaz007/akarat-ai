import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/listing_image.dart';
import '../../shared/models/listing.dart';

/// Full-screen photos and clips, swipeable, pinch to zoom; underneath, a
/// white sheet with every photo as a tile to jump to.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, this.initialIndex = 0, this.tags, this.title});
  final List<MediaItem> media;
  final int initialIndex;

  /// Hero tags matching the gallery's, so a photo grows into the viewer.
  final List<String>? tags;

  /// The listing's title, over the photo.
  final String? title;

  static Future<void> open(
    BuildContext context,
    List<MediaItem> media,
    int index, {
    List<String>? tags,
    String? title,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: Motion.of(context, Motion.normal),
        reverseTransitionDuration: Motion.of(context, Motion.normal),
        pageBuilder: (_, _, _) => MediaViewer(media: media, initialIndex: index, tags: tags, title: title),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  final _strip = ScrollController();
  late int _index = widget.initialIndex;

  static const double _tileWidth = 96;
  static const double _tileGap = 10;

  /// The sheet's height above the system inset: header, tiles, padding.
  static const double _sheet = 168;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(animate: false));
  }

  @override
  void dispose() {
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  /// Keeps the current photo's tile in view, centred where it can be.
  void _follow({bool animate = true}) {
    if (!_strip.hasClients) return;
    final pos = _strip.position;
    final target = (_index * (_tileWidth + _tileGap) - (pos.viewportDimension - _tileWidth) / 2).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    if (animate) {
      unawaited(_strip.animateTo(target, duration: Motion.of(context, Motion.normal), curve: Motion.standard));
    } else {
      _strip.jumpTo(target);
    }
  }

  void _go(int i) {
    if (i == _index) return;
    unawaited(HapticFeedback.selectionClick());
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || (i - _index).abs() > 2) {
      _pages.jumpToPage(i);
    } else {
      unawaited(_pages.animateToPage(i, duration: Motion.of(context, Motion.normal), curve: Motion.standard));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final sheet = _sheet * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.2) + bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          // Every layer is placed, so the stack takes the whole screen.
          fit: StackFit.expand,
          children: [
            // The photos run under the sheet's rounded corners.
            Positioned.fill(
              bottom: sheet - Radii.xl,
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.media.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _follow();
                },
                itemBuilder: (context, i) {
                  final m = widget.media[i];
                  if (m.isVideo) return _VideoPage(url: m.url, active: i == _index);
                  final photo = ListingImage(url: m.url, fit: BoxFit.contain);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // The same photo, decoded tiny and stretched: a soft
                      // wash of its own colours instead of black bars.
                      ExcludeSemantics(child: ListingImage(url: m.url, decodeWidth: 16)),
                      ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                      InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Center(
                          child: widget.tags == null || i >= widget.tags!.length
                              ? photo
                              : Hero(tag: widget.tags![i], transitionOnUserGestures: true, child: photo),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // A scrim so the back button and title read on bright photos.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, 0),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: Radii.tile,
                        child: IconButton(
                          tooltip: l.actionClose,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF16201D)),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                          child: Text(
                            widget.title ?? l.viewerPhotos,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: context.text.titleMedium?.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                      // Balances the back button, so the title is centred.
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: sheet,
              child: Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl + 2)),
                ),
                padding: EdgeInsets.only(top: Space.lg, bottom: bottom + Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(l.viewerPhotos, style: context.text.headlineSmall),
                            ),
                          ),
                          Text(
                            l.detailsMediaPosition(_index + 1, widget.media.length),
                            style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Expanded(
                      child: ListView.separated(
                        controller: _strip,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                        itemCount: widget.media.length,
                        separatorBuilder: (_, _) => const SizedBox(width: _tileGap),
                        itemBuilder: (context, i) => _Tile(
                          item: widget.media[i],
                          selected: i == _index,
                          label: l.detailsMediaPosition(i + 1, widget.media.length),
                          onTap: () => _go(i),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One photo (or clip) in the sheet: a rounded grey tile holding its
/// thumbnail; the one on screen is outlined.
class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.selected, required this.label, required this.onTap});
  final MediaItem item;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          width: _MediaViewerState._tileWidth,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: Radii.field,
            border: Border.all(color: selected ? c.forest : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md - 6),
            child: item.isVideo
                ? const ColoredBox(
                    color: Color(0xFF101614),
                    child: Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30)),
                  )
                : ListingImage(url: item.url, decodeWidth: _MediaViewerState._tileWidth),
          ),
        ),
      ),
    );
  }
}

/// A clip, loaded only when its page is shown and released when it leaves.
class _VideoPage extends StatefulWidget {
  const _VideoPage({required this.url, required this.active});
  final String url;
  final bool active;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_load());
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active && _c == null) unawaited(_load());
    if (!widget.active) unawaited(_c?.pause());
  }

  Future<void> _load() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() => _failed = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(uri);
    _c = c;
    try {
      await c.initialize();
      if (!mounted) return;
      await c.play();
      setState(() {});
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_c?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) {
      return Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white.withValues(alpha: 0.6), size: 48));
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (context, v, _) => AnimatedOpacity(
              opacity: v.isPlaying ? 0 : 1,
              duration: Motion.of(context, Motion.fast),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
            ),
          ),
          Positioned(
            left: Space.md,
            right: Space.md,
            // Clear of the sheet's rounded corners.
            bottom: Radii.xl + Space.md,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
