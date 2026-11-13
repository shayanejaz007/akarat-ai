import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/api_client.dart';
import '../assistant/assistant_stream.dart';
import 'advisor_models.dart';

/// The website's AI advisor (POST /api/ai/advisor): the same Claude-based
/// property advisor the site runs, answering in a stream. The app's sign-in
/// token rides along (apiClientProvider), so signed-in readers get the
/// higher daily allowance.
class AdvisorApi {
  AdvisorApi(this._dio);
  final Dio _dio;

  Stream<StreamEvent> ask({required String message, required String lang, String? transcript, CancelToken? cancel}) =>
      postNdjson(_dio, '/api/ai/advisor', {
        'message': message,
        'lang': lang,
        'transcript': ?transcript,
      }, cancel: cancel);
}

final advisorApiProvider = Provider<AdvisorApi>((ref) => AdvisorApi(ref.watch(apiClientProvider)));

final advisorProvider = NotifierProvider<AdvisorController, AdvisorState>(AdvisorController.new);

/// The conversation with the advisor: one reader message, then the
/// advisor's answer filling in as its events arrive. Kept while the app runs,
/// like the website keeps it for the browser tab.
class AdvisorController extends Notifier<AdvisorState> {
  CancelToken? _cancel;

  /// Longest message the advisor accepts (INPUT.maxMessageChars on the server).
  static const maxChars = 2000;

  @override
  AdvisorState build() {
    ref.onDispose(() => _cancel?.cancel());
    return const AdvisorState();
  }

  void _touch() => state = state.copyWith();

  Future<void> send(String text, {required String lang}) async {
    final message = text.trim();
    if (message.isEmpty || state.busy) return;
    final reply = AdvisorTurn.assistant();
    state = state.copyWith(turns: [...state.turns, AdvisorTurn.user(message), reply]);
    if (message.length > maxChars) {
      reply
        ..status = TurnStatus.error
        ..error = 'too_long';
      _touch();
      return;
    }
    final cancel = _cancel = CancelToken();
    final events = ref
        .read(advisorApiProvider)
        .ask(message: message, lang: lang, transcript: state.transcript, cancel: cancel);
    try {
      await for (final e in events) {
        if (cancel.isCancelled) break;
        _apply(reply, e);
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      if (reply.status == TurnStatus.working) {
        reply.status = cancel.isCancelled ? TurnStatus.stopped : TurnStatus.done;
        reply.current = null;
        if (cancel.isCancelled) reply.notices.add((kind: 'stopped', lang: null));
      }
      _touch();
    }
  }

  void _apply(AdvisorTurn reply, StreamEvent e) {
    switch (e['t']) {
      case 'status':
        final step = AdvisorStep(
          str(e['s']),
          q: e['q'] is String ? e['q'] as String : null,
          host: e['host'] is String ? e['host'] as String : null,
        );
        reply.current = step;
        // "thinking" and "writing" describe the advisor, not a step of work.
        if (step.s != 'thinking' && step.s != 'writing') reply.steps.add(step);
      case 'text':
        final d = str(e['d']);
        if (d.isEmpty) return;
        final last = reply.parts.isNotEmpty ? reply.parts.last : null;
        if (last is TextPart) {
          last.text += d;
        } else {
          reply.parts.add(TextPart(d));
        }
        reply.current = const AdvisorStep('writing');
      case 'cite':
        final numbers = citeNumbers(e['n']);
        if (numbers.isEmpty) return;
        final last = reply.parts.isNotEmpty ? reply.parts.last : null;
        if (last is TextPart) last.text += citeMarker(numbers);
      case 'source':
        if (e['s'] is Map) {
          final s = AdvisorSource.fromJson((e['s']! as Map).cast<String, Object?>());
          reply.sources
            ..removeWhere((x) => x.n == s.n)
            ..add(s)
            ..sort((a, b) => a.n.compareTo(b.n));
        }
      case 'cards':
        final cards = [
          for (final c in (e['items'] is List ? e['items']! as List : const []))
            if (c is Map) AdvisorCard.fromJson(c.cast<String, Object?>()),
        ].whereType<AdvisorCard>().toList();
        if (cards.isNotEmpty) reply.parts.add(CardsPart(cards));
      case 'compare':
        reply.parts.add(ComparePart(CompareTable.fromJson(e)));
      case 'criteria':
        if (e['c'] is Map) state = state.copyWith(criteria: (e['c']! as Map).cast<String, Object?>());
      case 'followups':
        reply.followups = [
          for (final f in (e['items'] is List ? e['items']! as List : const []))
            if (f is String && f.trim().isNotEmpty) f.trim(),
        ];
      case 'notice':
        reply.notices.add((kind: str(e['kind']), lang: e['lang'] is String ? e['lang'] as String : null));
      case 'redact':
        reply
          ..parts.clear()
          ..sources.clear()
          ..redacted = str(e['reason'], 'refused');
      case 'done':
        if (e['transcript'] is String) state = state.copyWith(transcript: e['transcript'] as String);
        reply
          ..status = TurnStatus.done
          ..current = null;
      case 'error':
        reply
          ..status = TurnStatus.error
          ..error = str(e['code'], 'unavailable')
          ..current = null;
    }
    _touch();
  }

  /// Stops the answer being written. What arrived so far stays.
  void stop() => _cancel?.cancel();

  /// A new conversation: the advisor forgets this one.
  void reset() {
    _cancel?.cancel();
    state = const AdvisorState().copyWith(turns: const [], clearCriteria: true);
  }

  /// Sends the last question again, after an error.
  Future<void> retry({required String lang}) async {
    final turns = state.turns;
    if (turns.length < 2 || state.busy) return;
    final question = turns[turns.length - 2];
    if (!question.user) return;
    state = state.copyWith(turns: turns.sublist(0, turns.length - 2));
    await send(question.text, lang: lang);
  }

  /// Drops one criterion from the search: asked of the advisor in words,
  /// as the website does, so it can re-run the search and say what changed.
  Future<void> removeCriterion(String label, {required String lang}) =>
      send(lang == 'ar' ? 'احذف هذا الشرط من البحث: $label' : 'Remove this from my search: $label', lang: lang);
}
