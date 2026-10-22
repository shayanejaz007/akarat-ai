import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../core/widgets/akarat_logo_animated.dart';
import 'theme/tokens.dart';

/// The opening, and the app's loading screen while it starts: the Akarat.ai
/// intro video (the splash kit's Higgsfield reveal, take A), full screen.
///
/// 1. The first frame is the native launch screen exactly: the logo on black,
///    drawn as vectors (no image to decode, so nothing holds it up).
/// 2. The intro is prepared from the moment the app starts, with nothing else
///    competing, and cross-fades in once a frame of it is drawn; it plays to
///    its end, fitted to the screen on the black of its own edges. Muted,
///    never interrupting the reader's audio, never keeping the screen on.
/// 3. The app starts working once the intro is playing ([start]), and is put
///    on screen behind it only when the reveal has settled, so its first,
///    heaviest frames cannot make the intro stutter. The splash then fades
///    into it as the intro ends; a tap, or Skip, ends it sooner.
/// 4. If the clip cannot play at once, the coded build of the same logo plays
///    instead; if it is merely slow (not playing 4 s after the screen is up),
///    the logo stays, a fine gold line shows the app is loading, and the app
///    follows as soon as it is ready. A ready app is let through within 8 s
///    of the screen being up, unless the intro is still playing.
/// 6. On Android the clip is prepared natively as the engine starts
///    (android/app/src/main/kotlin/ai/akarat/app/IntroPlayer.kt), which gets
///    it on screen well before video_player could; elsewhere video_player.
/// 5. With reduced motion, or a screen reader on: the still logo, briefly.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key, required this.start, this.language, this.clip = true, this.onScreen});

  /// Starts the app: what its first screen needs, then the app itself.
  final Future<Widget> Function() start;

  /// The interface language once known ('en' or 'ar'), for the Skip label.
  final Future<String?>? language;

  /// Whether to play the intro; the coded build alone when false.
  final bool clip;

  /// When the first frame is on screen, which everything here is timed from
  /// (on a slow phone the graphics take a while to start). The engine's own
  /// signal by default; tests, which have no graphics, pass their own.
  final Future<void>? onScreen;

  Future<void> get _onScreen => onScreen ?? WidgetsBinding.instance.waitUntilFirstFrameRasterized;

  /// The intro's own edges, and the native launch screen's background.
  static const ground = Color(0xFF000000);

  /// The logo's width on the native launch screen, which the first frame
  /// matches. The launch images (android/app/src/main/res/drawable-*/
  /// splash_icon.png and splash_mark.png, ios/Runner/Assets.xcassets/
  /// LaunchImage.imageset) are cut from the same drawing by
  /// test/visual/launch_logo_test.dart, centred on the lockup.
  static const launchLogoWidth = 140.38;

  /// The lockup within the logo's 1080-unit drawing: its width and centre.
  static const _lockupWidth = 911.5;
  static const _lockupCentre = Offset(541.75, 497.25);

  static const clipAsset = 'assets/splash/intro.mp4';

  /// The intro's length.
  static const clipLength = Duration(milliseconds: 5040);

  /// When the reveal has settled (the logo finished, only a held frame
  /// left): the app can be put on screen behind it unseen.
  static const settled = Duration(milliseconds: 3600);

  /// Where the logo's 1080-unit drawing goes so that its lockup is [width]
  /// wide and centred on [centre].
  static Rect logoBox(Offset centre, double width) {
    final k = width / _lockupWidth;
    return Rect.fromLTWH(centre.dx - _lockupCentre.dx * k, centre.dy - _lockupCentre.dy * k, 1080 * k, 1080 * k);
  }

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> {
  Future<Widget>? _starting;
  Widget? _built;
  Widget? _app;
  bool _mayShow = false;
  bool _appDrawn = false;
  bool _gone = false;
  final _safety = <Timer>[];

  @override
  void initState() {
    super.initState();
    // Whatever the intro does, the app starts, and shows, in good time:
    // counted from the first frame on screen, as everything here is (a slow
    // graphics start must not eat the intro's time).
    unawaited(
      widget._onScreen.then((_) {
        if (!mounted) return;
        _safety
          ..add(Timer(const Duration(seconds: 4), _start))
          ..add(Timer(const Duration(seconds: 7), _show));
      }),
    );
  }

  @override
  void dispose() {
    for (final t in _safety) {
      t.cancel();
    }
    super.dispose();
  }

  void _start() {
    if (_starting != null || !mounted) return;
    final starting = widget.start();
    _starting = starting;
    unawaited(
      starting.then(
        (app) {
          _built = app;
          _mount();
        },
        onError: (Object error, StackTrace stack) {
          // Reported as an uncaught start-up failure always was; the splash
          // stays, as the launch screen did.
          FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'app start'));
        },
      ),
    );
  }

  void _show() {
    _start();
    _mayShow = true;
    _mount();
  }

  void _mount() {
    if (!mounted || _app != null || !_mayShow || _built == null) return;
    setState(() => _app = _built);
    // Leave only once the app has drawn a frame behind the splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _appDrawn = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        ?app,
        if (!_gone)
          MediaQuery.fromView(
            view: View.of(context),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: _Splash(
                clip: widget.clip,
                language: widget.language,
                appDrawn: _appDrawn,
                onStart: _start,
                onShow: _show,
                onGone: () => setState(() => _gone = true),
                screenUp: widget._onScreen,
              ),
            ),
          ),
      ],
    );
  }
}

enum _Mode { video, vector, still }

class _Splash extends StatefulWidget {
  const _Splash({
    required this.clip,
    required this.language,
    required this.appDrawn,
    required this.onStart,
    required this.onShow,
    required this.onGone,
    required this.screenUp,
  });
  final bool clip;
  final Future<String?>? language;
  final bool appDrawn;

  /// The app may start its work now.
  final VoidCallback onStart;

  /// The app may go on screen behind the splash now.
  final VoidCallback onShow;
  final VoidCallback onGone;

  /// When the first frame is on screen.
  final Future<void> screenUp;

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with TickerProviderStateMixin, WidgetsBindingObserver {
  /// The intro taking over from the launch screen's logo.
  late final _introIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  late final _exit = AnimationController(vsync: this);
  late final _skipIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  late _Mode _mode;
  bool _introDone = false;
  bool _skip = false;
  bool _leaving = false;
  final _timers = <Timer>[];

  /// Within the first moments on screen: a clip failing now never showed
  /// at all, and the coded build can take its place unnoticed.
  bool _early = true;
  String _lang = 'ar';

  _Clip? _clip;
  bool _videoShowing = false;
  bool _screenUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final platform = WidgetsBinding.instance.platformDispatcher;
    final features = platform.accessibilityFeatures;
    _mode = features.disableAnimations || features.accessibleNavigation
        ? _Mode.still
        : (widget.clip ? _Mode.video : _Mode.vector);
    // The app's rule: English or Arabic as the device is, Arabic otherwise;
    // then the reader's own choice, once preferences are read.
    _lang = platform.locale.languageCode == 'en' ? 'en' : 'ar';
    unawaited(
      widget.language?.then((lang) {
        if (mounted && (lang == 'en' || lang == 'ar')) setState(() => _lang = lang!);
      }, onError: (Object _) {}),
    );
    // Prepared from the very first moment (on Android, natively, as the
    // engine starts), before anything else is started.
    if (_mode == _Mode.video) {
      unawaited(_openClip());
    } else {
      unawaited(_NativeClip.discard());
    }
    // The rest is timed from the first frame on screen: on a slow device the
    // graphics take a while to start, and the clip cannot until they have.
    unawaited(widget.screenUp.then((_) => _onScreen()));
  }

  void _onScreen() {
    if (!mounted) return;
    _after(const Duration(milliseconds: 1200), () => _early = false);
    _screenUp = true;
    // Played from the first frame on screen, so none of it is missed.
    _clip?.play();
    // However the intro goes, a ready app is let through within 8 s, unless
    // the intro is playing (it has a limit of its own).
    _after(const Duration(seconds: 8), () {
      if (_videoShowing) return;
      widget.onShow();
      _finishIntro();
    });
    switch (_mode) {
      case _Mode.still:
        widget.onShow();
        _after(const Duration(milliseconds: 900), _finishIntro);
      case _Mode.vector:
        widget.onShow();
        unawaited(_introIn.forward());
      case _Mode.video:
        // Not playing 4 s after the screen is up (a decoder too slow, or
        // none for it): carry on without it.
        _after(const Duration(seconds: 4), () {
          if (!_videoShowing) _withoutClip();
        });
    }
    if (_mode != _Mode.still) _after(const Duration(milliseconds: 1200), () => unawaited(_skipIn.forward()));
  }

  void _after(Duration d, VoidCallback f) => _timers.add(
    Timer(d, () {
      if (mounted) f();
    }),
  );

  Future<void> _openClip() async {
    final events = _ClipEvents(
      ready: () {
        if (mounted) setState(() {});
      },
      rendering: _onRendering,
      position: (p) {
        // The reveal has settled: the app goes on screen behind it unseen.
        if (p >= LaunchSplash.settled) widget.onShow();
      },
      completed: () {
        widget.onShow();
        _finishIntro();
      },
      failed: _withoutClip,
    );
    final clip = await _NativeClip.open(events) ?? _PlayerClip(events);
    if (!mounted || _mode != _Mode.video) {
      clip.dispose();
      return;
    }
    setState(() => _clip = clip);
    if (_screenUp && !_leaving) clip.play();
  }

  /// A frame of the intro is drawn: it takes over from the launch logo, and
  /// the app starts its work once it is in.
  void _onRendering() {
    if (!mounted || _videoShowing || _mode != _Mode.video) return;
    setState(() => _videoShowing = true);
    unawaited(_introIn.forward().whenComplete(() => widget.onStart()));
    // Its length and a margin, should it ever stall mid-way.
    _after(LaunchSplash.clipLength + const Duration(milliseconds: 800), () {
      widget.onShow();
      _finishIntro();
    });
  }

  /// The clip cannot play. Failing at once (no decoder for it), the coded
  /// build of the same logo plays instead; merely slow, the logo stays and
  /// the app follows as soon as it is ready.
  void _withoutClip() {
    if (!mounted || _mode != _Mode.video || _leaving) return;
    _clip?.dispose();
    _clip = null;
    final early = !_videoShowing && _early;
    widget.onShow();
    setState(() {
      _mode = early ? _Mode.vector : _Mode.still;
      _videoShowing = false;
    });
    if (early) {
      _introIn
        ..reset()
        ..forward();
    } else {
      _introIn.value = 0;
      _finishIntro();
    }
  }

  void _finishIntro() {
    if (_introDone) return;
    setState(() => _introDone = true);
    _maybeLeave();
  }

  @override
  void didUpdateWidget(_Splash old) {
    super.didUpdateWidget(old);
    if (widget.appDrawn && !old.appDrawn) _maybeLeave();
  }

  void _maybeLeave() {
    if (_leaving || !mounted || !widget.appDrawn) return;
    if (!_introDone && !_skip) return;
    setState(() => _leaving = true);
    _exit.duration = Duration(milliseconds: _mode == _Mode.still ? 300 : 550);
    unawaited(
      _exit.forward().whenComplete(() {
        if (mounted) widget.onGone();
      }),
    );
  }

  /// A tap, or Skip: the app as soon as it is there to show.
  void _onSkip() {
    _skip = true;
    widget.onShow();
    _maybeLeave();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final clip = _clip;
    if (clip == null || _introDone) return;
    if (state == AppLifecycleState.resumed && !_leaving) {
      clip.play();
    } else if (state != AppLifecycleState.resumed) {
      clip.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _timers) {
      t.cancel();
    }
    _introIn.dispose();
    _exit.dispose();
    _skipIn.dispose();
    _clip?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final centre = screen.center(Offset.zero);

    // The coded build is as large as the intro's logo (83% of its width).
    final vectorBox = LaunchSplash.logoBox(centre, math.min(screen.width, screen.height * 0.5625) * 0.83);
    final launchBox = LaunchSplash.logoBox(centre, LaunchSplash.launchLogoWidth);

    final intro = CurvedAnimation(parent: _introIn, curve: Curves.easeOut);
    // The launch logo is gone in the first half, so it never sits over the
    // intro's own first strokes.
    final logoOut = CurvedAnimation(
      parent: _introIn,
      curve: const Interval(0, 0.5, curve: Curves.easeIn),
    );
    final still = _mode == _Mode.still;
    final clip = _clip;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: IgnorePointer(
        ignoring: _leaving,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onSkip,
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _exit,
              builder: (context, child) {
                final t = Curves.fastOutSlowIn.transform(_exit.value);
                return Opacity(
                  opacity: 1 - t,
                  child: still ? child : Transform.scale(scale: 1 + 0.06 * t, child: child),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: LaunchSplash.ground),
                  // The intro, whole, fitted to the screen on its own black.
                  // Keyed, every layer: they come and go, and must never take
                  // over one another's state.
                  if (clip != null && clip.ready)
                    FadeTransition(
                      key: const ValueKey('intro'),
                      opacity: intro,
                      child: Center(
                        child: AspectRatio(aspectRatio: clip.aspect, child: clip.view()),
                      ),
                    ),
                  if (_mode == _Mode.vector)
                    Positioned.fromRect(
                      key: const ValueKey('build'),
                      rect: vectorBox,
                      child: FadeTransition(
                        opacity: intro,
                        child: AkaratLogoAnimated(size: vectorBox.width, onComplete: _finishIntro),
                      ),
                    ),
                  // The launch screen's logo, until the intro takes over.
                  Positioned.fromRect(
                    key: const ValueKey('launch'),
                    rect: launchBox,
                    child: FadeTransition(
                      opacity: ReverseAnimation(logoOut),
                      child: AkaratLogoAnimated(size: launchBox.width, animate: false),
                    ),
                  ),
                  // Waiting on the app after the intro: a line that shimmers
                  // under the logo until it is ready.
                  Positioned(
                    key: const ValueKey('loading'),
                    left: 0,
                    right: 0,
                    bottom: math.max(36, safe.bottom + 24),
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _introDone && !widget.appDrawn ? 1 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: _Shimmer(moving: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)),
                      ),
                    ),
                  ),
                  if (_mode != _Mode.still)
                    Positioned(
                      key: const ValueKey('skip'),
                      right: math.max(16, safe.right),
                      bottom: math.max(20, safe.bottom),
                      child: FadeTransition(
                        opacity: _skipIn,
                        child: _SkipPill(label: _lang == 'en' ? 'Skip' : 'تخطي', onTap: _onSkip),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the intro tells the splash.
class _ClipEvents {
  const _ClipEvents({
    required this.ready,
    required this.rendering,
    required this.position,
    required this.completed,
    required this.failed,
  });

  /// It can be put on screen (invisible until it renders).
  final VoidCallback ready;

  /// Its first frame is drawn.
  final VoidCallback rendering;
  final ValueChanged<Duration> position;
  final VoidCallback completed;
  final VoidCallback failed;
}

/// The intro's player.
abstract class _Clip {
  _Clip(this.events);
  final _ClipEvents events;

  bool get ready;
  double get aspect;
  Widget view();
  void play();
  void pause();
  void dispose();
}

/// On Android: the player MainActivity prepared as the engine started
/// (android/app/src/main/kotlin/ai/akarat/app/IntroPlayer.kt), drawing into
/// a Flutter texture, ready to play the moment the first frame is up.
class _NativeClip extends _Clip {
  _NativeClip._(super.events, this._id, this._aspect);

  static const _channel = MethodChannel('ai.akarat.app/intro');
  final int _id;
  final double _aspect;
  bool _disposed = false;
  Timer? _settle;

  /// The prepared intro, or null where there is none (iOS, tests, or a clip
  /// Android could not open); the splash then plays it through video_player.
  static Future<_NativeClip?> open(_ClipEvents events) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('texture');
      if (info == null) return null;
      final clip = _NativeClip._(events, info['id']! as int, (info['width']! as int) / (info['height']! as int));
      _channel.setMethodCallHandler(clip._on);
      return clip;
    } on Object {
      return null;
    }
  }

  /// No intro after all (reduced motion): free the prepared player.
  static Future<void> discard() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on Object {
      // Nothing was prepared.
    }
  }

  Future<Object?> _on(MethodCall call) async {
    if (_disposed) return null;
    switch (call.method) {
      case 'rendering':
        events.rendering();
        _settle = Timer(LaunchSplash.settled, () {
          if (!_disposed) events.position(LaunchSplash.settled);
        });
      case 'completed':
        events.completed();
      case 'error':
        events.failed();
    }
    return null;
  }

  @override
  bool get ready => true;

  @override
  double get aspect => _aspect;

  @override
  Widget view() => Texture(textureId: _id);

  @override
  void play() => unawaited(_channel.invokeMethod<void>('play').catchError((Object _) {}));

  @override
  void pause() => unawaited(_channel.invokeMethod<void>('pause').catchError((Object _) {}));

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settle?.cancel();
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('release').catchError((Object _) {}));
  }
}

/// Elsewhere (iOS): video_player, muted, never interrupting the reader's
/// audio, never keeping the screen awake.
class _PlayerClip extends _Clip {
  _PlayerClip(super.events) {
    unawaited(_init());
  }

  final _c = VideoPlayerController.asset(
    LaunchSplash.clipAsset,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, preventsDisplaySleepDuringVideoPlayback: false),
  );
  bool _initialized = false;
  bool _wanted = false;
  bool _shown = false;
  bool _ended = false;
  bool _disposed = false;

  Future<void> _init() async {
    try {
      await _c.initialize();
      if (_disposed) return;
      _initialized = true;
      _c.addListener(_onValue);
      await _c.setVolume(0);
      await _c.setLooping(false);
      events.ready();
      if (_wanted && !_disposed) await _c.play();
    } on Object {
      if (!_disposed) events.failed();
    }
  }

  void _onValue() {
    if (_disposed) return;
    final v = _c.value;
    if (v.hasError) {
      events.failed();
      return;
    }
    // A frame of it has actually been drawn once it is playing and moving.
    if (!_shown && v.isPlaying && v.position > Duration.zero) {
      _shown = true;
      events.rendering();
    }
    events.position(v.position);
    if (v.isCompleted && !_ended) {
      _ended = true;
      events.completed();
    }
  }

  @override
  bool get ready => _initialized;

  @override
  double get aspect => _c.value.aspectRatio;

  @override
  Widget view() => VideoPlayer(_c);

  @override
  void play() {
    _wanted = true;
    if (_initialized && !_disposed) unawaited(_c.play());
  }

  @override
  void pause() {
    _wanted = false;
    if (_initialized && !_disposed) unawaited(_c.pause());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _c.removeListener(_onValue);
    unawaited(_c.dispose());
  }
}

/// The kit's loading line: a gold glint passing along a faint track.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.moving});
  final bool moving;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.moving) unawaited(_c.repeat());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      width: 72,
      height: 2,
      child: ColoredBox(
        color: const Color(0x26E0AE45),
        child: widget.moving
            ? AnimatedBuilder(
                animation: _c,
                builder: (context, _) => FractionalTranslation(
                  translation: Offset(Curves.easeInOut.transform(_c.value) * 2 - 1, 0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0x00E0AE45), Color(0xFFE0AE45), Color(0x00E0AE45)]),
                    ),
                  ),
                ),
              )
            : null,
      ),
    ),
  );
}

/// The kit's Skip button: small, gold on smoke, with a full-size touch target.
class _SkipPill extends StatelessWidget {
  const _SkipPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x99141414),
          border: Border.all(color: const Color(0x59E0AE45)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label.toUpperCase(),
            textDirection: label == 'Skip' ? TextDirection.ltr : TextDirection.rtl,
            style: TextStyle(
              // Above the app's theme: the app's faces, named outright.
              fontFamily: label == 'Skip' ? AppFonts.text : AppFonts.arabic,
              color: const Color(0xFFE0AE45),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.4,
              height: 1,
            ),
          ),
        ),
      ),
    ),
  );
}
