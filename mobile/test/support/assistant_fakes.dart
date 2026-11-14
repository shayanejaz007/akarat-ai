import 'dart:async';

import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:dio/dio.dart';

/// The advisor's server, scripted: each question is answered with the
/// events [answer] returns for it.
class FakeAdvisorApi implements AdvisorApi {
  FakeAdvisorApi(this.answer);
  List<StreamEvent> Function(String message) answer;
  final asked = <({String message, String lang, String? transcript})>[];

  /// Which of the questions asked were spoken.
  final spoken = <bool>[];

  /// When set, the answer waits for it before it ends (to look at a turn
  /// while it is still being written).
  Completer<void>? hold;

  @override
  Stream<StreamEvent> ask({
    required String message,
    required String lang,
    String? transcript,
    bool voice = false,
    CancelToken? cancel,
  }) async* {
    asked.add((message: message, lang: lang, transcript: transcript));
    spoken.add(voice);
    final events = answer(message);
    for (final e in events) {
      if (cancel?.isCancelled ?? false) return;
      if (e['t'] == 'done' && hold != null) await hold!.future;
      yield e;
    }
  }
}
