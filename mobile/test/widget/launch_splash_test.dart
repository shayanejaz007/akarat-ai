import 'dart:async';

import 'package:akarat/app/launch_splash.dart';
import 'package:akarat/core/widgets/akarat_logo_animated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../support/fake_video_player.dart';

/// Stands in for the app: one button, counting taps.
class _App {
  int taps = 0;
  Widget build() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: TextButton(onPressed: () => taps++, child: const Text('The app')),
      ),
    ),
  );
}

const _phone = Size(390, 844);
const _phoneInsets = EdgeInsets.only(top: 47, bottom: 34);

/// The launch screen's logo (the finished logo, still).
Finder get _launchLogo => find.byWidgetPredicate((w) => w is AkaratLogoAnimated && !w.animate);
Finder get _build => find.byWidgetPredicate((w) => w is AkaratLogoAnimated && w.animate);
Finder get _clip => find.byKey(const ValueKey('fake-clip'));
Finder get _skip => find.text('SKIP');

/// Whether the splash is still over the app.
bool _splashUp() => _launchLogo.evaluate().isNotEmpty;

/// Opens the app (what main() builds once asked), its first frame on screen.
const _intro = MethodChannel('ai.akarat.app/intro');

Future<FakeVideoPlayerPlatform> _launch(
  WidgetTester tester, {
  required Future<Widget> Function() start,
  FakeVideoPlayerPlatform? player,
  Future<String?>? language,
  Size size = _phone,
  EdgeInsets insets = _phoneInsets,
  Future<Object?> Function(MethodCall call)? native,
}) async {
  final p = player ?? FakeVideoPlayerPlatform();
  VideoPlayerPlatform.instance = p;
  // Android's natively prepared intro: none unless a test plays one, so the
  // clip goes through video_player (as on iOS).
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_intro, native ?? (_) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_intro, null));
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  final padding = FakeViewPadding(
    left: insets.left * 3,
    top: insets.top * 3,
    right: insets.right * 3,
    bottom: insets.bottom * 3,
  );
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.reset);
  // No graphics in a test: the first frame counts as on screen once built.
  await tester.pumpWidget(LaunchSplash(start: start, language: language, onScreen: tester.binding.endOfFrame));
  await tester.pump();
  await tester.pump();
  return p;
}

/// Frames in small steps until the splash has gone (its fade is 550 ms);
/// fails if it is still up after [within].
Future<void> _leave(WidgetTester tester, {Duration within = const Duration(milliseconds: 900)}) async {
  final steps = within.inMilliseconds ~/ 50;
  for (var i = 0; i < steps && _splashUp(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(_splashUp(), isFalse, reason: 'gone within ${within.inMilliseconds} ms');
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pump();
}

double _opacityOf(WidgetTester tester, Finder f) {
  final fades = find.ancestor(of: f, matching: find.byType(FadeTransition));
  return tester.widgetList<FadeTransition>(fades).fold(1.0, (o, w) => o * w.opacity.value);
}

/// The native intro telling Dart something, as IntroPlayer.kt does.
Future<void> _nativeSays(WidgetTester tester, String event) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _intro.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(event)),
    (_) {},
  );
  await tester.pump();
}

void main() {
  testWidgets('on Android: the natively prepared intro plays from the first frame, then the app', (tester) async {
    final calls = <String>[];
    final player = await _launch(
      tester,
      start: () async => _App().build(),
      native: (call) async {
        calls.add(call.method);
        return call.method == 'texture' ? {'id': 7, 'width': 720, 'height': 1280} : null;
      },
    );
    await tester.pump();
    expect(calls, containsAllInOrder(['texture', 'play']), reason: 'played once the first frame is up');
    expect(player.created, isEmpty, reason: 'no second player');
    final texture = find.byWidgetPredicate((w) => w is Texture && w.textureId == 7);
    expect(texture, findsOneWidget);

    await _nativeSays(tester, 'rendering');
    await tester.pump(const Duration(milliseconds: 450));
    expect(_opacityOf(tester, texture), closeTo(1, 0.01));
    expect(_opacityOf(tester, _launchLogo), closeTo(0, 0.01));
    expect(tester.getRect(texture).width, closeTo(_phone.width, 0.5));

    await _nativeSays(tester, 'completed');
    await tester.pump();
    await _leave(tester);
    expect(calls.last, 'release', reason: 'the native player is let go');
  });

  testWidgets('opens as the launch screen; the intro plays to its end, then the app', (tester) async {
    final app = _App();
    var started = 0;
    final player = await _launch(
      tester,
      start: () async {
        started++;
        return app.build();
      },
    );

    // The first frame is the launch screen: the logo, mid-screen, its size.
    final box = LaunchSplash.logoBox(_phone.center(Offset.zero), LaunchSplash.launchLogoWidth);
    expect(tester.getRect(_launchLogo), box);

    // The intro: muted, once, never pausing the reader's audio or keeping
    // the screen on, fitted to the screen; it takes over once it is drawn.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 450));
    expect(player.created.single.dataSource.asset, LaunchSplash.clipAsset);
    expect(player.volumes, contains(0.0));
    expect(player.mixWithOthers, isTrue);
    expect(player.keepsScreenOn, isFalse);
    expect(player.looping, isFalse);
    expect(player.playing, isTrue);
    expect(_opacityOf(tester, _clip), closeTo(1, 0.01));
    expect(_opacityOf(tester, _launchLogo), closeTo(0, 0.01), reason: 'the launch logo has handed over');
    expect(tester.getRect(_clip).width, closeTo(_phone.width, 0.5), reason: 'the whole width');

    // The app starts its work once the intro is in, but is not put on
    // screen until the reveal has settled.
    expect(started, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('The app'), findsNothing);
    expect(_splashUp(), isTrue);

    player.finish();
    await tester.pump();
    await tester.pump();
    expect(find.text('The app'), findsOneWidget, reason: 'built behind the splash');
    await _leave(tester);
    // The player's own dispose waits on the real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.disposed, [0], reason: 'the decoder is released');
    await tester.tap(find.text('The app'));
    expect(app.taps, 1);
  });

  testWidgets('Skip shows after a moment, clear of the gesture bar, and ends the intro', (tester) async {
    final app = _App();
    await _launch(tester, start: () async => app.build());
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacityOf(tester, _skip), closeTo(0, 0.01), reason: 'not at once');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 450));
    expect(_opacityOf(tester, _skip), closeTo(1, 0.01));
    final pill = tester.getRect(_skip);
    expect(pill.bottom, lessThanOrEqualTo(_phone.height - _phoneInsets.bottom));
    expect(pill.right, lessThanOrEqualTo(_phone.width - 16));

    await tester.tap(_skip);
    await tester.pump();
    await _leave(tester);
    expect(app.taps, 0, reason: 'the tap did not reach the app');
  });

  testWidgets('a tap anywhere also skips', (tester) async {
    await _launch(tester, start: () async => _App().build());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(const Offset(195, 300));
    await tester.pump();
    await _leave(tester);
  });

  testWidgets('a slow start: after the intro, a gold line shimmers until the app is ready', (tester) async {
    final boot = Completer<Widget>();
    final player = await _launch(tester, start: () => boot.future);
    await tester.pump(const Duration(milliseconds: 600));
    final line = find.byWidgetPredicate((w) => w is AnimatedOpacity && w.child.runtimeType.toString() == '_Shimmer');
    expect(tester.widget<AnimatedOpacity>(line).opacity, 0, reason: 'not while the intro plays');

    player.finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<AnimatedOpacity>(line).opacity, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(_splashUp(), isTrue, reason: 'it waits for the app');

    boot.complete(_App().build());
    await tester.pump();
    await tester.pump();
    await _leave(tester);
    expect(find.text('The app'), findsOneWidget);
  });

  testWidgets('a clip that cannot play at all: the coded build of the logo instead', (tester) async {
    await _launch(tester, start: () async => _App().build(), player: FakeVideoPlayerPlatform(fails: true));
    await tester.pump();
    expect(_build, findsOneWidget);
    expect(_clip, findsNothing);
    await tester.pump(); // its clock starts on the frame after it is built
    await tester.pump(AkaratLogoAnimated.duration);
    await tester.pump();
    await _leave(tester);
  });

  testWidgets('a clip too slow to start: the logo stays, a line shows loading, then the app', (tester) async {
    await _launch(tester, start: () async => _App().build(), player: FakeVideoPlayerPlatform(stalls: true));
    await tester.pump(const Duration(milliseconds: 3900));
    expect(_splashUp(), isTrue);
    expect(_opacityOf(tester, _launchLogo), closeTo(1, 0.01), reason: 'the launch logo holds meanwhile');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_build, findsNothing, reason: 'no rebuild of a logo already on screen');
    await tester.pump();
    await _leave(tester);
  });

  testWidgets('an intro that stalls mid-way still lets the app through', (tester) async {
    await _launch(tester, start: () async => _App().build());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(tester, _clip), greaterThan(0));
    await tester.pump(const Duration(seconds: 5));
    expect(_splashUp(), isTrue, reason: 'still within the intro');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    await _leave(tester);
  });

  testWidgets('reduced motion: the still logo, no clip, no Skip, about a second', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final player = await _launch(tester, start: () async => _App().build());
    await tester.pump(const Duration(milliseconds: 500));
    expect(player.created, isEmpty);
    expect(_build, findsNothing);
    expect(_skip, findsNothing);
    expect(_opacityOf(tester, _launchLogo), closeTo(1, 0.01));
    await tester.pump(const Duration(milliseconds: 450));
    await _leave(tester, within: const Duration(milliseconds: 600));
  });

  testWidgets("Skip is in the reader's language", (tester) async {
    await _launch(tester, start: () async => _App().build(), language: Future.value('ar'));
    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text('تخطي'), findsOneWidget);
    expect(_skip, findsNothing);
    await tester.tap(find.text('تخطي'));
    await tester.pump();
    await _leave(tester);
  });

  testWidgets('sent to the background, the intro pauses; back, it plays on', (tester) async {
    final player = await _launch(tester, start: () async => _App().build());
    await tester.pump(const Duration(milliseconds: 600));
    expect(player.playing, isTrue);
    await _lifecycle(tester, AppLifecycleState.paused);
    expect(player.playing, isFalse);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(player.playing, isTrue);
    player.finish();
    await tester.pump();
    await tester.pump();
    await _leave(tester);
  });

  testWidgets('on a phone on its side the intro fits, and Skip clears the notch', (tester) async {
    const size = Size(844, 390);
    const insets = EdgeInsets.only(left: 47, right: 47, bottom: 21);
    final player = await _launch(tester, start: () async => _App().build(), size: size, insets: insets);
    await tester.pump(const Duration(milliseconds: 650));
    final clip = tester.getRect(_clip);
    expect(clip.top, greaterThanOrEqualTo(-0.5));
    expect(clip.bottom, lessThanOrEqualTo(size.height + 0.5));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.getRect(_skip).right, lessThanOrEqualTo(size.width - insets.right));
    player.finish();
    await tester.pump();
    await tester.pump();
    await _leave(tester);
  });
}
