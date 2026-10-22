import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why listening could not start or stopped early.
enum SpeechFailure {
  /// The reader refused the microphone (or speech recognition on iOS).
  denied,

  /// No speech recogniser on this device.
  unavailable,

  /// Nothing was heard.
  noSpeech,

  /// The recogniser needs a connection it does not have.
  network,

  /// Anything else the platform reports.
  other,
}

/// On-device speech recognition: Android's recogniser and Apple's Speech
/// framework. Audio stays with the platform; nothing is recorded or sent by
/// the app itself.
abstract class SpeechService {
  /// Asks for the microphone if needed. False when listening is impossible;
  /// [lastFailure] says why.
  Future<bool> prepare();

  SpeechFailure? get lastFailure;

  /// Locale ids the device can recognise, like `ar_JO` or `en_US`.
  Future<List<String>> localeIds();

  Future<void> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onWords,
    required void Function(double level) onLevel,
    required void Function(SpeechFailure failure) onFailure,
    required void Function() onDone,
  });

  Future<void> stop();
  Future<void> cancel();
}

final speechServiceProvider = Provider<SpeechService>((ref) => DeviceSpeechService());

/// The recognition locale for an interface language. Jordanian Arabic first,
/// then the closest Levantine variants, then any Arabic; US then any English.
String? pickSpeechLocale(List<String> available, String lang) {
  String norm(String id) => id.replaceAll('-', '_');
  final ids = available.map(norm).toList();
  final prefs = lang == 'ar'
      ? ['ar_JO', 'ar_PS', 'ar_LB', 'ar_SY', 'ar_SA', 'ar_AE', 'ar_EG']
      : ['en_US', 'en_GB', 'en_AU', 'en_IN'];
  for (final p in prefs) {
    final hit = ids.indexWhere((x) => x.toLowerCase() == p.toLowerCase());
    if (hit >= 0) return available[hit];
  }
  final prefix = '${lang}_';
  final any = ids.indexWhere((x) => x.toLowerCase().startsWith(prefix) || x.toLowerCase() == lang);
  return any >= 0 ? available[any] : null;
}

class DeviceSpeechService implements SpeechService {
  final _stt = SpeechToText();
  SpeechFailure? _failure;
  void Function(SpeechFailure)? _onFailure;
  void Function()? _onDone;

  @override
  SpeechFailure? get lastFailure => _failure;

  static SpeechFailure _classify(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('permission') || m.contains('denied') || m.contains('not authorized')) return SpeechFailure.denied;
    if (m.contains('no_match') || m.contains('speech_timeout') || m.contains('no speech')) {
      return SpeechFailure.noSpeech;
    }
    if (m.contains('network') || m.contains('server')) return SpeechFailure.network;
    if (m.contains('not_available') || m.contains('recognizer')) return SpeechFailure.unavailable;
    return SpeechFailure.other;
  }

  @override
  Future<bool> prepare() async {
    _failure = null;
    try {
      final ok = await _stt.initialize(
        onError: (SpeechRecognitionError e) {
          final f = _classify(e.errorMsg);
          _failure = f;
          _onFailure?.call(f);
        },
        onStatus: (status) {
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) _onDone?.call();
        },
      );
      if (!ok) {
        _failure = await _stt.hasPermission ? SpeechFailure.unavailable : SpeechFailure.denied;
      }
      return ok;
    } on Object catch (e) {
      _failure = _classify(e.toString());
      if (_failure == SpeechFailure.other) _failure = SpeechFailure.unavailable;
      return false;
    }
  }

  @override
  Future<List<String>> localeIds() async {
    final locales = await _stt.locales();
    return [for (final l in locales) l.localeId];
  }

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onWords,
    required void Function(double level) onLevel,
    required void Function(SpeechFailure failure) onFailure,
    required void Function() onDone,
  }) async {
    _onFailure = onFailure;
    _onDone = onDone;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => onWords(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: ListenMode.search,
        // A pause after speaking ends the request, as on a phone's own search.
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 45),
        cancelOnError: true,
        autoPunctuation: true,
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();
}
