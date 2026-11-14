import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../assistant/assistant_stream.dart' show citeClose, citeOpen;

/// How reading a reply aloud ended.
enum SpeakResult {
  spoken,

  /// The phone has no voice for that language: the reply is shown instead.
  noVoice,

  /// Silenced before it finished (interrupted, or the conversation closed).
  stopped,
  failed,
}

/// Reads text aloud with the phone's own voices (Android's text-to-speech
/// engine, Apple's speech synthesiser). Nothing is sent anywhere by the app.
abstract class Speaker {
  /// Completes when the text has been read, or could not be.
  Future<SpeakResult> speak(String text, {required String lang});

  Future<void> stop();
}

/// Overridable, so tests never touch the device's voices.
final speakerProvider = Provider<Speaker>((ref) => DeviceSpeaker());

/// The share of a text's letters that are Arabic.
double arabicShare(String text) {
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).length;
  if (letters == 0) return 0;
  return RegExp(r'[ء-يٮ-ۓ]').allMatches(text).length / letters;
}

/// A reply as it should be said: no markup, citation markers, table rows or
/// links. Cut at the end of a sentence when longer than [max].
String speakable(String text, {int max = 900}) {
  final table = RegExp(r'^\s*\|.*\|\s*$');
  final rule = RegExp(r'^\s*[-:| ]{3,}\s*$');
  final out = text
      .replaceAll(RegExp('$citeOpen[^$citeClose]*$citeClose'), '')
      .split('\n')
      .where((line) => !table.hasMatch(line) && !rule.hasMatch(line))
      .map((line) => line.replaceFirst(RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+'), '').replaceFirst(RegExp(r'^#+\s*'), ''))
      .join('\n')
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  if (out.length <= max) return out;
  final cut = out.substring(0, max);
  final end = ['. ', '؟ ', '? ', '! ', '\n'].map(cut.lastIndexOf).reduce((a, b) => a > b ? a : b);
  return (end > max * 0.5 ? cut.substring(0, end + 1) : cut).trim();
}

/// The voice to use for a language, from the ones the phone has: Jordanian
/// Arabic if there is one, then the common Arabic voices; US then any English.
String? pickVoiceLanguage(List<String> available, String lang) {
  String norm(String id) => id.replaceAll('_', '-').toLowerCase();
  final prefs = lang == 'ar' ? ['ar-JO', 'ar-SA', 'ar-001', 'ar-EG', 'ar-AE', 'ar'] : ['en-US', 'en-GB', 'en-AU', 'en'];
  for (final p in prefs) {
    for (final id in available) {
      if (norm(id) == p.toLowerCase()) return id;
    }
  }
  for (final id in available) {
    if (norm(id).startsWith('$lang-')) return id;
  }
  return null;
}

class DeviceSpeaker implements Speaker {
  final _tts = FlutterTts();
  bool _ready = false;
  int _run = 0;

  Future<void> _prepare() async {
    if (_ready) return;
    await _tts.awaitSpeakCompletion(true);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Listening leaves the audio session set for recording, which plays
      // quietly through the earpiece: speak through the speaker instead.
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
      ]);
    }
    _ready = true;
  }

  @override
  Future<SpeakResult> speak(String text, {required String lang}) async {
    final mine = ++_run;
    try {
      await _prepare();
      final languages = await _tts.getLanguages;
      final available = [
        if (languages is List)
          for (final l in languages) l.toString(),
      ];
      final voice = pickVoiceLanguage(available, lang);
      if (voice == null) return SpeakResult.noVoice;
      await _tts.setLanguage(voice);
      if (mine != _run) return SpeakResult.stopped;
      final result = await _tts.speak(text);
      if (mine != _run) return SpeakResult.stopped;
      return result == 1 ? SpeakResult.spoken : SpeakResult.failed;
    } on Object {
      return mine == _run ? SpeakResult.failed : SpeakResult.stopped;
    }
  }

  @override
  Future<void> stop() async {
    _run++;
    try {
      await _tts.stop();
    } on Object {
      // Nothing was being read.
    }
  }
}
