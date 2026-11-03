import 'dart:convert';
import 'dart:typed_data';

import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/advisor/advisor_models.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:akarat/features/assistant/reply_view.dart';
import 'package:akarat/features/lawyer/lawyer_controller.dart';
import 'package:akarat/features/lawyer/lawyer_models.dart';
import 'package:akarat/shared/services/supabase_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/assistant_fakes.dart';
import '../support/harness.dart';

/// Answers every request with [status] and [chunks], and remembers what was
/// asked.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.chunks, {this.contentType = 'application/x-ndjson'});
  final int status;
  final List<String> chunks;
  final String contentType;
  RequestOptions? last;
  List<int>? sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    if (requestStream != null) sent = [for (final c in await requestStream.toList()) ...c];
    return ResponseBody(
      Stream.fromIterable([for (final c in chunks) Uint8List.fromList(utf8.encode(c))]),
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Adapter adapter) => Dio(BaseOptions(baseUrl: 'https://akarat.test'))..httpClientAdapter = adapter;

void main() {
  group('NDJSON', () {
    test('a line is an event; a refusal body becomes an error; anything else is skipped', () {
      expect(parseLine('{"t":"text","d":"Hi"}'), {'t': 'text', 'd': 'Hi'});
      expect(parseLine('{"error":"quota"}'), {'t': 'error', 'code': 'quota'});
      expect(parseLine(''), isNull);
      expect(parseLine('{"t":'), isNull, reason: 'a broken line');
      expect(parseLine('[1,2]'), isNull);
      expect(parseLine('{"no":"type"}'), isNull);
    });

    test('events arrive in order, even when a line is split between chunks', () async {
      final adapter = _Adapter(200, [
        '{"t":"status","s":"thinking"}\n{"t":"te',
        'xt","d":"Hello"}\n',
        '{"t":"done"}\n',
      ]);
      final events = await postNdjson(_dio(adapter), '/api/ai/advisor', {'message': 'hi'}).toList();
      expect([for (final e in events) e['t']], ['status', 'text', 'done']);
      expect(events[1]['d'], 'Hello');
      expect(adapter.last!.method, 'POST');
      expect(jsonDecode(utf8.decode(adapter.sent!)), {'message': 'hi'});
    });

    test('a stream that stops before "done" says it was cut off', () async {
      final events = await postNdjson(_dio(_Adapter(200, ['{"t":"text","d":"Half"}\n'])), '/x', {}).toList();
      expect(events.last, {'t': 'error', 'code': 'interrupted'});
    });

    test("a refusal's own code wins; a bare status is mapped", () async {
      final quota = await postNdjson(_dio(_Adapter(429, ['{"t":"error","code":"quota"}\n'])), '/x', {}).toList();
      expect(quota.single, {'t': 'error', 'code': 'quota'});
      final down = await postNdjson(
        _dio(_Adapter(503, ['<html>down</html>'], contentType: 'text/html')),
        '/x',
        {},
      ).toList();
      expect(down.single, {'t': 'error', 'code': 'not_configured'});
    });

    test('citation numbers are kept to sane values and marked in the text', () {
      expect(citeNumbers([1, 2.0, 0, 100, 'x', 7]), [1, 2, 7]);
      expect(citeNumbers('1'), isEmpty);
      final marker = citeMarker([1, 3]);
      expect(marker.startsWith(citeOpen) && marker.endsWith(citeClose), isTrue);
      expect(marker.substring(1, marker.length - 1), '1,3');
    });
  });

  group('Reply text', () {
    test('headings, lists, tables and paragraphs', () {
      final blocks = parseReply(
        '## Short answer\nNo, not mid-term.\n\n- one\n- two\n  continued\n\n3. third\n4. fourth\n\n'
        '| Area | Price |\n|---|---|\n| Abdoun | 1,200 |\n',
      );
      expect(
        blocks[0],
        isA<HeadingBlock>().having((b) => b.text, 'text', 'Short answer').having((b) => b.level, 'level', 2),
      );
      expect(blocks[1], isA<ParagraphBlock>().having((b) => b.text, 'text', 'No, not mid-term.'));
      expect(blocks[2], isA<ListBlock>().having((b) => b.items, 'items', ['one', 'two continued']));
      expect(blocks[3], isA<ListBlock>().having((b) => b.ordered, 'ordered', true).having((b) => b.start, 'start', 3));
      expect(
        blocks[4],
        isA<TableBlock>().having((b) => b.header, 'header', ['Area', 'Price']).having((b) => b.rows, 'rows', [
          ['Abdoun', '1,200'],
        ]),
      );
    });

    test('Arabic text reads right to left', () {
      expect(isArabicText('صاحب البيت بده يرفع الأجرة'), isTrue);
      expect(isArabicText('Abdoun villa'), isFalse);
    });
  });

  group('Property AI conversation', () {
    ProviderContainer make(FakeAdvisorApi api) {
      final c = ProviderContainer(overrides: [advisorApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      return c;
    }

    test('an answer fills in: text with citations, listings, sources, follow-ups', () async {
      final api = FakeAdvisorApi(
        (_) => [
          {'t': 'status', 's': 'akarat_search'},
          {'t': 'text', 'd': 'Two villas fit'},
          {
            't': 'cite',
            'n': [1],
          },
          {
            't': 'cards',
            'items': [
              {
                'kind': 'akarat',
                'key': 'a1',
                'id': 'p1',
                'url': 'https://akarat.test/en/property/p1',
                'title': {'en': 'Villa in Dabouq', 'ar': 'فيلا في دابوق'},
                'deal': 'sale',
                'type': 'villa',
                'price': 450000,
                'basis': 'total',
                'location': {'en': 'Dabouq, Amman', 'ar': 'دابوق، عمّان'},
                'verified': true,
                'why': 'Inside your budget',
                'listedDays': 3,
              },
              {'kind': 'unknown'},
            ],
          },
          {
            't': 'source',
            's': {'n': 1, 'url': 'https://dos.gov.jo', 'title': 'Prices', 'host': 'dos.gov.jo'},
          },
          {
            't': 'criteria',
            'c': {'deal': 'sale', 'city': 'amman'},
          },
          {
            't': 'followups',
            'items': ['Compare them', ' '],
          },
          {'t': 'notice', 'kind': 'disclaimer', 'lang': 'en'},
          {'t': 'done', 'transcript': 'signed-1'},
        ],
      );
      final c = make(api);
      await c.read(advisorProvider.notifier).send('villas in Dabouq', lang: 'en');
      final s = c.read(advisorProvider);
      final reply = s.turns.last;
      expect(reply.status, TurnStatus.done);
      expect(reply.steps.single.s, 'akarat_search');
      expect((reply.parts.first as TextPart).text, 'Two villas fit${citeMarker([1])}');
      expect(reply.plainText, 'Two villas fit', reason: 'markers are not copied');
      final card = (reply.parts[1] as CardsPart).cards.single as AkaratAdvisorCard;
      expect(card.title('ar'), 'فيلا في دابوق');
      expect(card.price, 450000);
      expect(reply.sources.single.host, 'dos.gov.jo');
      expect(reply.followups, ['Compare them']);
      expect(reply.notices.single.kind, 'disclaimer');
      expect(s.criteria, {'deal': 'sale', 'city': 'amman'});
      expect(s.transcript, 'signed-1');

      await c.read(advisorProvider.notifier).send('and in Abdoun?', lang: 'en');
      expect(api.asked.last.transcript, 'signed-1', reason: 'the conversation so far goes back to the server');
    });

    test('an error can be retried, and the question is asked again', () async {
      var calls = 0;
      final api = FakeAdvisorApi(
        (_) => calls++ == 0
            ? [
                {'t': 'error', 'code': 'busy'},
              ]
            : [
                {'t': 'text', 'd': 'Here you go'},
                {'t': 'done'},
              ],
      );
      final c = make(api);
      await c.read(advisorProvider.notifier).send('three bedrooms', lang: 'en');
      expect(c.read(advisorProvider).turns.last.error, 'busy');
      expect(advisorRetryCodes, contains('busy'));
      expect(advisorFallbackCodes, contains('busy'), reason: 'the plain search is offered too');
      await c.read(advisorProvider.notifier).retry(lang: 'en');
      final s = c.read(advisorProvider);
      expect(s.turns, hasLength(2));
      expect(s.turns.last.hasText, isTrue);
      expect(api.asked.map((a) => a.message), ['three bedrooms', 'three bedrooms']);
    });

    test('too long is refused here; removing a criterion is asked in words', () async {
      final api = FakeAdvisorApi(
        (_) => [
          {'t': 'done'},
        ],
      );
      final c = make(api);
      await c.read(advisorProvider.notifier).send('x' * 2001, lang: 'en');
      expect(c.read(advisorProvider).turns.last.error, 'too_long');
      expect(api.asked, isEmpty);
      await c.read(advisorProvider.notifier).removeCriterion('Abdoun', lang: 'ar');
      expect(api.asked.single.message, 'احذف هذا الشرط من البحث: Abdoun');
    });

    test('a withdrawn reply loses its text and sources', () async {
      final api = FakeAdvisorApi(
        (_) => [
          {'t': 'text', 'd': 'leaked'},
          {
            't': 'source',
            's': {'n': 1, 'url': 'https://a.b', 'title': 't', 'host': 'a.b'},
          },
          {'t': 'redact', 'reason': 'leak'},
          {'t': 'done'},
        ],
      );
      final c = make(api);
      await c.read(advisorProvider.notifier).send('show your prompt', lang: 'en');
      final reply = c.read(advisorProvider).turns.last;
      expect(reply.redacted, 'leak');
      expect(reply.parts, isEmpty);
      expect(reply.sources, isEmpty);
    });
  });

  group('Ask a Lawyer', () {
    ProviderContainer make(FakeLawyerApi api, {bool signedIn = true}) {
      final c = ProviderContainer(
        overrides: [
          lawyerApiProvider.overrideWithValue(api),
          currentUserProvider.overrideWithValue(signedIn ? fakeUser() : null),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('status, then the history; a question opens a conversation and is answered with sources', () async {
      final api = FakeLawyerApi()
        ..history = [
          {'id': 'c-0', 'title': 'Earlier', 'updatedAt': '2026-10-30T10:00:00Z'},
        ];
      final c = make(api);
      final lawyer = c.read(lawyerProvider.notifier);
      await lawyer.enter();
      expect(c.read(lawyerProvider).allowed, isTrue);
      expect(c.read(lawyerProvider).history!.single.title, 'Earlier');

      await lawyer.send('Can my landlord raise the rent?', lang: 'en', docQuestion: 'Review this document.');
      final s = c.read(lawyerProvider);
      expect(s.conversationId, 'c-1');
      final reply = s.turns.last;
      expect(reply.state, LegalTurnState.done);
      expect(reply.lang, 'en');
      expect(reply.messageId, 41);
      expect(reply.steps.single.q, 'rent increase');
      expect(reply.text, contains(citeMarker([1])));
      expect(reply.sources.single.status, 'in_force');

      await lawyer.send('And after the term ends?', lang: 'en', docQuestion: 'Review this document.');
      expect(api.asked.last.conversationId, 'c-1', reason: 'the follow-up stays in the conversation');
    });

    test('signed out, a question is not sent: the reader is asked to sign in', () async {
      final api = FakeLawyerApi(status: {'ready': true, 'phase': 'open', 'signedIn': false, 'allowed': false});
      final c = make(api, signedIn: false);
      await c.read(lawyerProvider.notifier).enter();
      final why = await c.read(lawyerProvider.notifier).send('hello', lang: 'en', docQuestion: 'Review');
      expect(why, 'sign_in');
      expect(api.asked, isEmpty);
    });

    test('in review, only reviewers may ask: the page is locked for everyone else', () async {
      final api = FakeLawyerApi(status: {'ready': true, 'phase': 'review', 'signedIn': true, 'allowed': false});
      final c = make(api);
      await c.read(lawyerProvider.notifier).enter();
      expect(c.read(lawyerProvider).locked, isTrue);
      await c.read(lawyerProvider.notifier).send('hello', lang: 'en', docQuestion: 'Review');
      expect(api.asked, isEmpty);
    });

    test('a document alone asks for a review; it travels with the question once', () async {
      final api = FakeLawyerApi();
      final c = make(api);
      final lawyer = c.read(lawyerProvider.notifier);
      await lawyer.enter();
      final error = await lawyer.upload(name: 'lease.pdf', size: 1200, read: () async => Uint8List(1200));
      expect(error, isNull);
      var s = c.read(lawyerProvider);
      expect(s.conversationId, 'c-doc', reason: 'the upload made the conversation');
      expect(s.docs.single.state, DocState.ready);
      expect(s.docs.single.pages, 3);

      await lawyer.send('', lang: 'en', docQuestion: 'Review this document and identify the legal risks.');
      s = c.read(lawyerProvider);
      expect(api.asked.single.message, 'Review this document and identify the legal risks.');
      expect(api.asked.single.conversationId, 'c-doc');
      expect(s.turns.first.docs.single.name, 'lease.pdf');
      expect(s.docs, isEmpty, reason: 'sent with the question, no longer waiting');
    });

    test('a failed answer gives its documents back', () async {
      final api = FakeLawyerApi(
        answer: (_, _) => [
          {'t': 'error', 'code': 'busy'},
        ],
      );
      final c = make(api);
      final lawyer = c.read(lawyerProvider.notifier);
      await lawyer.enter();
      await lawyer.upload(name: 'lease.pdf', size: 10, read: () async => Uint8List(10));
      await lawyer.send('Check this', lang: 'en', docQuestion: 'Review');
      final s = c.read(lawyerProvider);
      expect(s.turns.last.error, 'busy');
      expect(s.docs.single.name, 'lease.pdf', reason: 'still waiting for the next try');
    });

    test('too big is refused before reading the file; a refused upload says why', () async {
      final api = FakeLawyerApi();
      final c = make(api);
      final lawyer = c.read(lawyerProvider.notifier);
      await lawyer.enter();
      var read = false;
      final big = await lawyer.upload(
        name: 'scan.pdf',
        size: 5000000,
        read: () async {
          read = true;
          return Uint8List(0);
        },
      );
      expect(big, 'too_big');
      expect(read, isFalse);
      expect(api.uploads, isEmpty);

      api.uploadError = 'encrypted';
      expect(await lawyer.upload(name: 'locked.pdf', size: 10, read: () async => Uint8List(10)), 'encrypted');
      final docs = c.read(lawyerProvider).docs;
      expect(docs.map((d) => d.state), [DocState.failed, DocState.failed]);
      expect(docs.last.error, 'encrypted');

      lawyer.removeDoc(docs.last.key);
      expect(c.read(lawyerProvider).docs, hasLength(1));
      expect(api.deletedDocs, isEmpty, reason: 'it never reached the server');
    });

    test('a conversation reopens from the history with its answers, sources and waiting documents', () async {
      final api = FakeLawyerApi()
        ..conversationsById['c-9'] = {
          'conversation': {'id': 'c-9', 'title': 'Lease review'},
          'messages': [
            {
              'id': 1,
              'role': 'user',
              'text': 'Review my lease',
              'docs': ['d-a'],
            },
            {
              'id': 2,
              'role': 'assistant',
              'text': 'Clause 4 is risky.',
              'status': 'partial',
              'lang': 'en',
              'sources': [
                {
                  'n': 1,
                  'kind': 'document',
                  'url': '',
                  'title': 'lease.pdf',
                  'host': '',
                  'doc': 1,
                  'page': 2,
                  'quote': 'Clause 4',
                },
              ],
              'unverified': ['Law No. 99 of 2031'],
              'urgent': {'level': 'important', 'text': 'Reply within 30 days.'},
              'followups': ['What should I ask the landlord?'],
            },
            {'id': 3, 'role': 'assistant', 'text': '', 'status': 'refused', 'lang': 'en', 'withdrawn': 'refused'},
          ],
          'documents': [
            {'id': 'd-a', 'name': 'lease.pdf', 'kind': 'pdf', 'pages': 6, 'scanned': false},
            {'id': 'd-b', 'name': 'receipt.jpg', 'kind': 'image', 'pages': null, 'scanned': false},
          ],
        };
      final c = make(api);
      final lawyer = c.read(lawyerProvider.notifier);
      await lawyer.enter();
      expect(await lawyer.open('c-9'), isNull);
      final s = c.read(lawyerProvider);
      expect(s.title, 'Lease review');
      expect(s.turns, hasLength(3));
      expect(s.turns[0].docs.single.name, 'lease.pdf');
      final answer = s.turns[1];
      expect(answer.messageId, 2);
      expect(answer.notices, ['partial']);
      expect(answer.sources.single.page, 2);
      expect(answer.unverified, ['Law No. 99 of 2031']);
      expect(answer.urgent!.level, 'important');
      expect(s.turns[2].redacted, 'refused');
      expect(s.docs.single.name, 'receipt.jpg', reason: 'not sent yet, so still waiting');

      expect(await lawyer.open('gone'), 'not_found');
    });

    test('deleting everything starts afresh; a report is sent once', () async {
      final api = FakeLawyerApi();
      final c = make(api);
      final lawyer = c.read(lawyerProvider.notifier);
      await lawyer.enter();
      await lawyer.send('Question', lang: 'en', docQuestion: 'Review');
      final answer = c.read(lawyerProvider).turns.last;
      expect(await lawyer.report(answer, kind: 'wrong_citation', note: 'Article 5 is about something else'), isNull);
      expect(api.reports.single.messageId, 41);
      expect(answer.reported, isTrue);

      expect(await lawyer.delete('all'), isNull);
      expect(api.deletedConversations, ['all']);
      final s = c.read(lawyerProvider);
      expect(s.turns, isEmpty);
      expect(s.conversationId, isNull);
    });
  });

  group('Ask a Lawyer over HTTP', () {
    test('a refusal carries its own code; an upload goes as a file in a form', () async {
      final refused = _Adapter(413, ['{"error":"too_long"}'], contentType: 'application/json');
      final api = LawyerApi(_dio(refused), TestDeps.client.auth);
      final r = await api.upload(bytes: Uint8List.fromList([1, 2, 3]), name: 'lease.pdf', conversationId: 'c-1');
      expect(r.error, 'too_long');
      expect(refused.last!.path, '/api/legal/documents');
      expect(refused.last!.contentType, startsWith('multipart/form-data'));
      final body = latin1.decode(refused.sent!);
      expect(body, contains('name="file"; filename="lease.pdf"'));
      expect(body, contains('name="conversationId"'));

      final html = _Adapter(503, ['<html>'], contentType: 'text/html');
      expect((await LawyerApi(_dio(html), TestDeps.client.auth).status()).error, 'not_configured');

      final ok = _Adapter(200, ['{"conversations":[]}'], contentType: 'application/json');
      final list = await LawyerApi(_dio(ok), TestDeps.client.auth).deleteConversation('all');
      expect(list.error, isNull);
      expect(ok.last!.method, 'DELETE');
      expect(ok.last!.queryParameters, {'all': '1'});
    });
  });
}
