import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient;

import '../../core/networking/api_client.dart';
import '../../shared/services/supabase_providers.dart';
import '../assistant/assistant_stream.dart';
import 'lawyer_models.dart';

/// What one of the JSON routes answered: its body, or an error code.
typedef LawyerResult = ({Map<String, Object?>? data, String? error});

/// Ask a Lawyer's routes on the website (`/api/legal/*`): the same service
/// the site's page talks to. Every call carries the reader's session token
/// (apiClientProvider): these routes serve signed-in accounts only, and Row
/// Level Security keeps each account's conversations and documents its own.
class LawyerApi {
  LawyerApi(this._dio, this._auth);
  final Dio _dio;
  final GoTrueClient _auth;

  /// The client sends no token once it has expired, and the route would then
  /// answer "sign in": refresh it first when it is due.
  Future<void> _fresh() async {
    final session = _auth.currentSession;
    if (session == null || !session.isExpired) return;
    try {
      await _auth.refreshSession();
    } on Object {
      // The route will say "sign in".
    }
  }

  static const _statusError = {
    401: 'sign_in',
    403: 'not_open',
    404: 'not_found',
    409: 'too_many_documents',
    413: 'too_big',
    429: 'rate_limited',
    503: 'not_configured',
  };

  Future<LawyerResult> _call(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    String? contentType,
  }) async {
    await _fresh();
    try {
      final res = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          validateStatus: (_) => true,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
          contentType: contentType,
        ),
      );
      final body = res.data is Map ? (res.data! as Map).cast<String, Object?>() : null;
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        final code = body?['error'];
        return (data: null, error: code is String && code.isNotEmpty ? code : _statusError[status] ?? 'unavailable');
      }
      return (data: body ?? const <String, Object?>{}, error: null);
    } on DioException catch (e) {
      return (
        data: null,
        error: switch (e.type) {
          DioExceptionType.connectionError ||
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout => offlineCode,
          _ => 'unavailable',
        },
      );
    }
  }

  Future<LawyerResult> status() => _call('GET', '/api/legal/status');

  /// The answer as it is written: `conversation` first, then the answer's
  /// events, then `saved` and `done` (or `error`).
  Stream<StreamEvent> ask({
    required String message,
    required String lang,
    String? conversationId,
    CancelToken? cancel,
  }) async* {
    await _fresh();
    yield* postNdjson(_dio, '/api/legal/ask', {
      'message': message,
      'lang': lang,
      'conversationId': ?conversationId,
    }, cancel: cancel);
  }

  Future<LawyerResult> conversations() => _call('GET', '/api/legal/conversations');

  Future<LawyerResult> conversation(String id) => _call('GET', '/api/legal/conversations', query: {'id': id});

  /// One conversation, or every one of the account's with [id] 'all'.
  Future<LawyerResult> deleteConversation(String id) =>
      _call('DELETE', '/api/legal/conversations', query: id == 'all' ? {'all': '1'} : {'id': id});

  /// A file into the conversation (a new one when [conversationId] is null).
  /// The server screens it, measures it, seals it and keeps it in the
  /// account's own private folder.
  Future<LawyerResult> upload({required Uint8List bytes, required String name, String? conversationId}) {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: name),
      'conversationId': ?conversationId,
    });
    return _call(
      'POST',
      '/api/legal/documents',
      data: form,
      contentType: 'multipart/form-data; boundary=${form.boundary}',
      // Up to 4 MB over a phone's connection, then a reading by the server.
      sendTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 45),
    );
  }

  Future<LawyerResult> deleteDocument(String id) => _call('DELETE', '/api/legal/documents', query: {'id': id});

  Future<LawyerResult> feedback({required int messageId, required String kind, String note = ''}) =>
      _call('POST', '/api/legal/feedback', data: {'messageId': messageId, 'kind': kind, 'note': note});
}

final lawyerApiProvider = Provider<LawyerApi>(
  (ref) => LawyerApi(ref.watch(apiClientProvider), ref.watch(supabaseClientProvider).auth),
);

final lawyerProvider = NotifierProvider<LawyerController, LawyerState>(LawyerController.new);

/// Ask a Lawyer: the open conversation, the documents waiting to go with the
/// next question, and the account's history. The conversation itself lives
/// on the server, sealed and private to the account; the app keeps nothing
/// of it on the device.
class LawyerController extends Notifier<LawyerState> {
  CancelToken? _cancel;

  /// Numbers each upload's chip: a clock can give two quick uploads the same time.
  var _uploads = 0;

  /// Longest question the service accepts (INPUT.maxMessageChars).
  static const maxChars = 4000;

  @override
  LawyerState build() {
    ref.onDispose(() => _cancel?.cancel());
    // Another account, or none: nothing of the last one stays on screen.
    ref.listen(currentUserProvider.select((u) => u?.id), (before, now) {
      if (before == now) return;
      _cancel?.cancel();
      state = const LawyerState();
      unawaited(enter());
    });
    return const LawyerState();
  }

  LawyerApi get _api => ref.read(lawyerApiProvider);

  void _touch() => state = state.copyWith();

  /// On arrival, and whenever the account changes: may this reader ask, and
  /// what have they asked before.
  Future<void> enter() async {
    final r = await _api.status();
    final status = r.data == null ? LawyerStatus.down : LawyerStatus.fromJson(r.data!);
    state = state.copyWith(status: status);
    if (status.allowed) {
      await loadHistory();
    } else {
      state = state.copyWith(clearHistory: true);
    }
  }

  Future<void> loadHistory() async {
    final r = await _api.conversations();
    if (r.error != null) {
      state = state.copyWith(historyError: true);
      return;
    }
    final rows = r.data!['conversations'];
    state = state.copyWith(
      history: [
        for (final c in (rows is List ? rows : const []))
          if (c is Map) LegalConversation.fromJson(c.cast<String, Object?>()),
      ],
      historyError: false,
    );
  }

  /// Asks [raw]. A document on its own is a request to review it
  /// ([docQuestion]). Returns a reason it was not sent, for the screen to
  /// show: 'sign_in', or 'doc_busy' while a file is still uploading.
  Future<String?> send(String raw, {required String lang, required String docQuestion}) async {
    final waiting = state.docs.where((d) => d.state == DocState.ready).toList();
    var text = raw.trim();
    if (text.length > maxChars) text = text.substring(0, maxChars);
    if (text.isEmpty && waiting.isNotEmpty) text = docQuestion;
    if (text.isEmpty || state.busy) return null;
    if (!ref.read(isSignedInProvider)) return 'sign_in';
    if (!state.allowed) return null;
    if (state.uploading) return 'doc_busy';

    final reply = LegalTurn.assistant();
    state = state.copyWith(
      docs: state.docs.where((d) => d.state != DocState.ready).toList(),
      turns: [
        ...state.turns,
        LegalTurn.user(text, docs: waiting),
        reply,
      ],
    );
    final cancel = _cancel = CancelToken();
    final events = _api.ask(message: text, lang: lang, conversationId: state.conversationId, cancel: cancel);
    try {
      await for (final e in events) {
        if (cancel.isCancelled) break;
        _apply(reply, e);
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      if (reply.state == LegalTurnState.working) {
        reply.state = cancel.isCancelled ? LegalTurnState.stopped : LegalTurnState.done;
        if (cancel.isCancelled) reply.notices.add('stopped');
      }
      reply.current = null;
      // A failed answer saved nothing, so its documents are still waiting.
      if (reply.state == LegalTurnState.error && state.turns.contains(reply)) {
        state = state.copyWith(docs: [...waiting, ...state.docs]);
      }
      _touch();
    }
    if (!state.turns.contains(reply)) return null;
    if (reply.state == LegalTurnState.error && (reply.error == 'sign_in' || reply.error == 'not_open')) {
      await enter();
    } else if (reply.state != LegalTurnState.error) {
      // The conversation just moved to the top of the history.
      await loadHistory();
    }
    return null;
  }

  void _apply(LegalTurn reply, StreamEvent e) {
    switch (e['t']) {
      case 'conversation':
        final id = str(e['id']);
        if (id.isEmpty) return;
        final title = str(e['title']);
        // New, or renamed from its document's name to its first question:
        // the history list needs to hear about it.
        final known = state.history?.where((h) => h.id == id).firstOrNull;
        state = state.copyWith(conversationId: id, title: title);
        if (known == null || known.title != title) unawaited(loadHistory());
      case 'status':
        final s = str(e['s']);
        if (s.isEmpty || s == 'thinking') return;
        final step = LegalStep(s, q: str(e['q']), host: str(e['host']));
        reply.current = step;
        if (reply.steps.isEmpty || !reply.steps.last.same(step)) reply.steps.add(step);
      case 'text':
        final d = str(e['d']);
        if (d.isEmpty) return;
        reply
          ..text += d
          ..current = const LegalStep('writing');
      case 'cite':
        // Private-use markers the reply view turns into numbered chips; the
        // server strips that range from the model's text, so none is forged.
        final numbers = citeNumbers(e['n']);
        if (numbers.isNotEmpty) reply.text += citeMarker(numbers);
      case 'source':
        if (e['s'] is Map) {
          final s = LegalSource.fromJson((e['s']! as Map).cast<String, Object?>());
          if (!reply.sources.any((x) => x.n == s.n)) reply.sources.add(s);
        }
      case 'unverified':
        final refs = e['refs'];
        reply.unverified = [for (final r in (refs is List ? refs : const []).take(30)) '$r'];
      case 'urgent':
        reply.urgent = (level: e['level'] == 'urgent' ? 'urgent' : 'important', text: str(e['text']));
      case 'followups':
        final items = e['items'];
        reply.followups = [
          for (final f in (items is List ? items : const []).take(4))
            if (f is String && f.trim().isNotEmpty) f.trim(),
        ];
      case 'redact':
        reply
          ..text = ''
          ..followups = const []
          ..redacted = e['reason'] == 'leak' ? 'leak' : 'refused';
      case 'notice':
        final kind = str(e['kind']);
        if (kind.isNotEmpty) reply.notices.add(kind);
      case 'saved':
        reply.messageId = numOrNull(e['messageId'])?.toInt();
      case 'done':
        reply
          ..state = LegalTurnState.done
          ..lang = e['lang'] == 'ar' ? 'ar' : 'en'
          ..current = null;
      case 'error':
        reply
          ..state = LegalTurnState.error
          ..error = str(e['code'], 'unavailable')
          ..current = null;
    }
    _touch();
  }

  /// Stops the answer being written. What arrived so far stays.
  void stop() => _cancel?.cancel();

  /// A fresh conversation. Documents waiting in the one being left stay with
  /// it, on the server, and come back when it is reopened.
  void newConversation() {
    _cancel?.cancel();
    state = state.copyWith(turns: const [], clearConversation: true, title: '', docs: const []);
  }

  /// Asks the last question again, after an error.
  Future<String?> retry({required String lang, required String docQuestion}) async {
    final turns = state.turns;
    if (turns.length < 2 || state.busy) return null;
    final question = turns[turns.length - 2];
    if (!question.user) return null;
    state = state.copyWith(turns: turns.sublist(0, turns.length - 2));
    return send(question.text, lang: lang, docQuestion: docQuestion);
  }

  /// Opens a conversation from the history. Returns an error code, or null.
  Future<String?> open(String id) async {
    if (state.busy || id.isEmpty) return null;
    final r = await _api.conversation(id);
    if (r.error != null) {
      if (r.error == 'not_found') unawaited(loadHistory());
      return r.error;
    }
    final data = r.data!;
    final documents = [
      for (final d in (data['documents'] is List ? data['documents']! as List : const []))
        if (d is Map) LegalDoc.fromJson(d.cast<String, Object?>()),
    ];
    final byId = {for (final d in documents) d.id: d};
    final sent = <String>{};
    final turns = <LegalTurn>[];
    for (final raw in (data['messages'] is List ? data['messages']! as List : const [])) {
      if (raw is! Map) continue;
      final m = raw.cast<String, Object?>();
      if (m['role'] == 'user') {
        final ids = [for (final x in (m['docs'] is List ? m['docs']! as List : const [])) '$x'];
        sent.addAll(ids);
        turns.add(LegalTurn.user(str(m['text']), docs: [for (final x in ids) ?byId[x]]));
        continue;
      }
      final status = str(m['status']);
      final withdrawn = m['withdrawn'];
      final turn = LegalTurn.assistant()
        ..text = str(m['text'])
        ..state = status == 'stopped' ? LegalTurnState.stopped : LegalTurnState.done
        ..messageId = numOrNull(m['id'])?.toInt()
        ..lang = m['lang'] == 'ar' ? 'ar' : (m['lang'] == 'en' ? 'en' : null)
        ..redacted = withdrawn == null ? null : (withdrawn == 'leak' ? 'leak' : 'refused')
        ..unverified = [for (final x in (m['unverified'] is List ? m['unverified']! as List : const [])) '$x']
        ..followups = [
          for (final f in (m['followups'] is List ? m['followups']! as List : const []))
            if (f is String && f.trim().isNotEmpty) f.trim(),
        ];
      for (final s in (m['sources'] is List ? m['sources']! as List : const [])) {
        if (s is Map) turn.sources.add(LegalSource.fromJson(s.cast<String, Object?>()));
      }
      final urgent = m['urgent'];
      if (urgent is Map) {
        turn.urgent = (level: urgent['level'] == 'urgent' ? 'urgent' : 'important', text: str(urgent['text']));
      }
      if (status == 'partial') turn.notices.add('partial');
      if (status == 'stopped') turn.notices.add('stopped');
      turns.add(turn);
    }
    final conversation = data['conversation'] is Map ? (data['conversation']! as Map).cast<String, Object?>() : null;
    _cancel?.cancel();
    state = state.copyWith(
      turns: turns,
      conversationId: id,
      title: str(conversation?['title']),
      docs: [
        for (final d in documents)
          if (!sent.contains(d.id)) d,
      ],
    );
    return null;
  }

  /// Deletes one conversation, or with [id] 'all' every one of the
  /// account's. Returns an error code, or null.
  Future<String?> delete(String id) async {
    final r = await _api.deleteConversation(id);
    if (r.error != null) return r.error;
    if (id == 'all' || id == state.conversationId) newConversation();
    await loadHistory();
    return null;
  }

  /// Adds a file of [size] bytes to the conversation; [read] is called only
  /// once it is known to fit. Returns an error code, or null.
  Future<String?> upload({required String name, required int size, required Future<Uint8List> Function() read}) async {
    final key = 'f${++_uploads}';
    final kind = LegalDoc.kindOf(name);
    final limit = state.status?.maxBytes ?? 4000000;
    final tooBig = size > limit;
    state = state.copyWith(
      docs: [
        ...state.docs,
        LegalDoc(
          key: key,
          name: name,
          kind: kind,
          state: tooBig ? DocState.failed : DocState.uploading,
          error: tooBig ? 'too_big' : null,
        ),
      ],
    );
    if (tooBig) return 'too_big';
    final created = state.conversationId == null;
    Uint8List bytes;
    try {
      bytes = await read();
    } on Object {
      state = state.copyWith(
        docs: [for (final d in state.docs) d.key == key ? d.copyWith(state: DocState.failed, error: 'other') : d],
      );
      return 'other';
    }
    final r = await _api.upload(bytes: bytes, name: name, conversationId: state.conversationId);
    // Left behind by "new conversation" while it was uploading.
    if (!state.docs.any((d) => d.key == key)) return null;
    if (r.error != null) {
      state = state.copyWith(
        docs: [for (final d in state.docs) d.key == key ? d.copyWith(state: DocState.failed, error: r.error) : d],
      );
      if (r.error == 'sign_in' || r.error == 'not_open') unawaited(enter());
      return r.error;
    }
    final data = r.data!;
    final doc = data['document'] is Map
        ? (data['document']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    state = state.copyWith(
      conversationId:
          state.conversationId ?? (data['conversationId'] is String ? data['conversationId'] as String : null),
      title: state.title.isEmpty ? str(data['title']) : state.title,
      docs: [
        for (final d in state.docs)
          d.key == key
              ? d.copyWith(
                  id: str(doc['id']),
                  name: str(doc['name'], name),
                  kind: str(doc['kind'], kind),
                  pages: numOrNull(doc['pages'])?.toInt(),
                  scanned: doc['scanned'] == true,
                  state: DocState.ready,
                )
              : d,
      ],
    );
    if (created) unawaited(loadHistory());
    return null;
  }

  /// Takes a document out of the conversation, here and on the server.
  void removeDoc(String key) {
    final doc = state.docs.where((d) => d.key == key).firstOrNull;
    if (doc == null) return;
    state = state.copyWith(
      docs: [
        for (final d in state.docs)
          if (d.key != key) d,
      ],
    );
    final id = doc.id;
    if (id != null) unawaited(_api.deleteDocument(id));
  }

  /// Reports a problem with an answer (or that it helped). Returns an error
  /// code, or null.
  Future<String?> report(LegalTurn turn, {required String kind, String note = ''}) async {
    final id = turn.messageId;
    if (id == null) return 'not_found';
    final r = await _api.feedback(messageId: id, kind: kind, note: note);
    if (r.error != null) return r.error;
    turn.reported = true;
    _touch();
    return null;
  }
}
