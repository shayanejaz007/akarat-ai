import 'dart:async';
import 'dart:typed_data';

import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:akarat/features/lawyer/lawyer_controller.dart';
import 'package:dio/dio.dart';

/// The advisor's server, scripted: each question is answered with the
/// events [answer] returns for it.
class FakeAdvisorApi implements AdvisorApi {
  FakeAdvisorApi(this.answer);
  List<StreamEvent> Function(String message) answer;
  final asked = <({String message, String lang, String? transcript})>[];

  /// When set, the answer waits for it before it ends (to look at a turn
  /// while it is still being written).
  Completer<void>? hold;

  @override
  Stream<StreamEvent> ask({
    required String message,
    required String lang,
    String? transcript,
    CancelToken? cancel,
  }) async* {
    asked.add((message: message, lang: lang, transcript: transcript));
    final events = answer(message);
    for (final e in events) {
      if (cancel?.isCancelled ?? false) return;
      if (e['t'] == 'done' && hold != null) await hold!.future;
      yield e;
    }
  }
}

/// Ask a Lawyer's server, scripted and kept in memory.
class FakeLawyerApi implements LawyerApi {
  FakeLawyerApi({
    Map<String, Object?>? status,
    List<StreamEvent> Function(String message, String? conversationId)? answer,
  }) : statusBody =
           status ??
           {
             'ready': true,
             'phase': 'open',
             'signedIn': true,
             'allowed': true,
             'reviewer': false,
             'limits': {'maxBytes': 4000000, 'maxPages': 30, 'maxDocs': 4},
           },
       answer = answer ?? _defaultAnswer;

  Map<String, Object?> statusBody;
  List<StreamEvent> Function(String message, String? conversationId) answer;
  final asked = <({String message, String? conversationId})>[];
  final uploads = <({String name, int bytes, String? conversationId})>[];
  final deletedDocs = <String>[];
  final deletedConversations = <String>[];
  final reports = <({int messageId, String kind, String note})>[];
  List<Map<String, Object?>> history = [];
  Map<String, Map<String, Object?>> conversationsById = {};
  String? uploadError;

  static List<StreamEvent> _defaultAnswer(String message, String? conversationId) => [
    {'t': 'conversation', 'id': conversationId ?? 'c-1', 'title': message},
    {'t': 'status', 's': 'library', 'q': 'rent increase'},
    {'t': 'text', 'd': '## Short answer\nThe landlord cannot raise the rent mid-term'},
    {
      't': 'cite',
      'n': [1],
    },
    {'t': 'text', 'd': '.'},
    {
      't': 'source',
      's': {
        'n': 1,
        'kind': 'library',
        'url': 'https://example.gov.jo/law',
        'title': 'Owners and Tenants Law, Article 5',
        'host': 'example.gov.jo',
        'status': 'in_force',
        'verified': '2026-10-01',
      },
    },
    {'t': 'saved', 'messageId': 41},
    {'t': 'done', 'lang': 'en'},
  ];

  @override
  Future<LawyerResult> status() async => (data: statusBody, error: null);

  @override
  Stream<StreamEvent> ask({
    required String message,
    required String lang,
    String? conversationId,
    CancelToken? cancel,
  }) async* {
    asked.add((message: message, conversationId: conversationId));
    for (final e in answer(message, conversationId)) {
      if (cancel?.isCancelled ?? false) return;
      yield e;
    }
  }

  @override
  Future<LawyerResult> conversations() async => (data: {'conversations': history}, error: null);

  @override
  Future<LawyerResult> conversation(String id) async {
    final c = conversationsById[id];
    return c == null ? (data: null, error: 'not_found') : (data: c, error: null);
  }

  @override
  Future<LawyerResult> deleteConversation(String id) async {
    deletedConversations.add(id);
    if (id == 'all') {
      history = [];
    } else {
      history = [
        for (final h in history)
          if (h['id'] != id) h,
      ];
    }
    return (data: <String, Object?>{'deleted': true}, error: null);
  }

  @override
  Future<LawyerResult> upload({required Uint8List bytes, required String name, String? conversationId}) async {
    uploads.add((name: name, bytes: bytes.length, conversationId: conversationId));
    if (uploadError != null) return (data: null, error: uploadError);
    return (
      data: <String, Object?>{
        'conversationId': conversationId ?? 'c-doc',
        'title': name,
        'document': {
          'id': 'd-${uploads.length}',
          'name': name,
          'kind': 'pdf',
          'pages': 3,
          'scanned': false,
          'bytes': bytes.length,
        },
      },
      error: null,
    );
  }

  @override
  Future<LawyerResult> deleteDocument(String id) async {
    deletedDocs.add(id);
    return (data: <String, Object?>{'deleted': true}, error: null);
  }

  @override
  Future<LawyerResult> feedback({required int messageId, required String kind, String note = ''}) async {
    reports.add((messageId: messageId, kind: kind, note: note));
    return (data: <String, Object?>{'saved': true}, error: null);
  }
}
