import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// One event of an assistant's streamed answer.
///
/// The website's two assistants (the AI advisor at `/api/ai/advisor` and Ask
/// a Lawyer at `/api/legal/ask`) answer as NDJSON: one JSON object per line,
/// each with a `t` naming what it is ("text", "cards", "source", "done"...).
/// The app reads exactly what the website's page reads, so both show the same
/// answer, the same sources and the same notices.
typedef StreamEvent = Map<String, Object?>;

/// Error codes the page knows how to explain, shared with the website.
const offlineCode = 'offline';
const interruptedCode = 'interrupted';

/// Posts [body] to [path] on the website and yields the answer's events as
/// they arrive. Errors become an event (`{t: error, code}`), never an
/// exception, so the screen has one way to show them. Cancelling [cancel]
/// ends the stream quietly.
///
/// [idle] is how long the stream may go without a byte: research can pause
/// for a while between events, but a dead connection must not hang forever.
Stream<StreamEvent> postNdjson(
  Dio dio,
  String path,
  Map<String, Object?> body, {
  CancelToken? cancel,
  Duration idle = const Duration(seconds: 75),
}) async* {
  final Response<ResponseBody> res;
  try {
    res = await dio.post<ResponseBody>(
      path,
      data: body,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: idle,
        // A refusal (429, 413...) carries its reason as NDJSON too.
        validateStatus: (_) => true,
        headers: {'Accept': 'application/x-ndjson'},
      ),
    );
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) return;
    yield {'t': 'error', 'code': _codeOf(e)};
    return;
  }
  final stream = res.data?.stream;
  if (stream == null) {
    yield {'t': 'error', 'code': interruptedCode};
    return;
  }
  final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
  var sawError = false;
  var sawEnd = false;
  try {
    final lines = stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      final event = parseLine(line);
      if (event == null) continue;
      if (event['t'] == 'error') sawError = true;
      if (event['t'] == 'done') sawEnd = true;
      yield event;
    }
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) return;
    if (!sawError) yield {'t': 'error', 'code': _codeOf(e, midStream: true)};
    return;
  } on FormatException {
    if (!sawError) yield {'t': 'error', 'code': interruptedCode};
    return;
  }
  if (cancel?.isCancelled ?? false) return;
  // A refusal with a plain JSON body ({error: code}) rather than NDJSON, or
  // a stream that stopped before saying it was done.
  if (!ok && !sawError) {
    yield {'t': 'error', 'code': _statusCode(res.statusCode)};
  } else if (ok && !sawEnd && !sawError) {
    yield {'t': 'error', 'code': interruptedCode};
  }
}

/// One line of NDJSON as an event, or null for a blank or broken line. A
/// `{error: code}` object (what the routes send for a refusal) becomes an
/// error event.
StreamEvent? parseLine(String line) {
  if (line.trim().isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final event = decoded.cast<String, Object?>();
  if (event['t'] == null && event['error'] is String) return {'t': 'error', 'code': event['error']};
  return event['t'] is String ? event : null;
}

String _codeOf(DioException e, {bool midStream = false}) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
      return midStream ? interruptedCode : offlineCode;
    default:
      return interruptedCode;
  }
}

String _statusCode(int? status) => switch (status) {
  401 => 'sign_in',
  403 => 'not_open',
  404 => 'not_found',
  409 => 'busy',
  413 => 'too_long',
  429 => 'rate_limited',
  503 => 'not_configured',
  _ => 'unavailable',
};

/// Citations travel in the answer's text as their numbers between
/// [citeOpen] and [citeClose], two private-use characters: the app puts them
/// there from the server's `cite` events, as the website's page does. The
/// server removes that range from what the model writes, so a marker can
/// only come from a real citation.
const citeOpen = '\ue000';
const citeClose = '\ue001';
String citeMarker(List<int> numbers) => '$citeOpen${numbers.join(',')}$citeClose';

/// The numbers in a `cite` event, kept to sane values.
List<int> citeNumbers(Object? raw) => [
  if (raw is List)
    for (final n in raw)
      if (n is num && n >= 1 && n <= 99) n.toInt(),
];

/// A string field of an event, or [fallback].
String str(Object? v, [String fallback = '']) => v is String ? v : fallback;

/// A number field of an event, or null.
num? numOrNull(Object? v) => v is num ? v : null;
