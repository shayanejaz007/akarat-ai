import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video player that plays nothing but records how it was asked to play.
/// Install with `VideoPlayerPlatform.instance = FakeVideoPlayerPlatform()`.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({this.fails = false, this.stalls = false, this.size = const Size(720, 1280)});

  /// The clip cannot be decoded.
  final bool fails;

  /// The clip never gets ready (a slow decoder).
  final bool stalls;
  final Size size;

  final created = <VideoCreationOptions>[];
  final volumes = <double>[];
  final disposed = <int>[];
  bool? mixWithOthers;
  bool? keepsScreenOn;
  bool? looping;
  bool playing = false;
  Duration _position = Duration.zero;
  final _events = <int, StreamController<VideoEvent>>{};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async => this.mixWithOthers = mixWithOthers;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    created.add(options);
    final id = _nextId++;
    // Closed in dispose(), as the real player closes its own.
    // ignore: close_sinks
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    if (fails) {
      events.addError(PlatformException(code: 'VideoError', message: 'The clip cannot be decoded'));
    } else if (!stalls) {
      events.add(VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(seconds: 4), size: size));
    }
    return id;
  }

  /// The clip plays to its end.
  void finish() {
    _position = const Duration(seconds: 4);
    for (final events in _events.values) {
      events.add(VideoEvent(eventType: VideoEventType.completed));
    }
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(int playerId, bool preventsDisplaySleep) async =>
      keepsScreenOn = preventsDisplaySleep;

  @override
  Future<void> setVolume(int playerId, double volume) async => volumes.add(volume);

  @override
  Future<void> setLooping(int playerId, bool looping) async => this.looping = looping;

  @override
  Future<void> play(int playerId) async {
    playing = true;
    _position = const Duration(milliseconds: 120);
  }

  @override
  Future<void> pause(int playerId) async => playing = false;

  @override
  Future<Duration> getPosition(int playerId) async => _position;

  @override
  Future<void> seekTo(int playerId, Duration position) async => _position = position;

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    playing = false;
    await _events.remove(playerId)?.close();
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(key: ValueKey('fake-clip'), color: Color(0xFF2E7D32));
}
