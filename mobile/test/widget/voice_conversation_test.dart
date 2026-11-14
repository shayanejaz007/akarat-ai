import 'dart:async';

import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/advisor/voice_conversation.dart';
import 'package:akarat/features/ai_hub/ai_hub_screen.dart';
import 'package:akarat/features/ai_search/voice/speaker.dart';
import 'package:akarat/features/ai_search/voice/speech_service.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/assistant_fakes.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

/// The orb breathes while the conversation is open, so the screen never
/// "settles": step time forward instead.
Future<void> step(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<StreamEvent> _answer(String message) {
  final arabic = arabicShare(message) > 0.3;
  return [
    {'t': 'status', 's': 'akarat_search'},
    {'t': 'text', 'd': arabic ? 'لقيتلك **فيلتين** بدابوق' : 'I found **two villas** in Dabouq'},
    {
      't': 'cite',
      'n': [1],
    },
    {'t': 'text', 'd': arabic ? '. بدك أرخص؟' : '. Do you want something cheaper?'},
    {'t': 'done', 'transcript': 't1'},
  ];
}

Future<List<Override>> _deps(FakeAdvisorApi api, FakeSpeechService speech, FakeSpeaker speaker) async => [
  ...await TestDeps(speech: speech, speaker: speaker).overrides(),
  advisorApiProvider.overrideWithValue(api),
];

void main() {
  test('a reply is said without its markup, citations, tables or links', () {
    expect(
      speakable(
        '**Found 3** apartments${citeMarker([1, 2])} in Abdoun.\n\n- First: 85,000 JOD\n'
        '| a | b |\n|---|---|\nSee https://example.com/x now',
      ),
      'Found 3 apartments in Abdoun.\nFirst: 85,000 JOD\nSee now',
    );
    final long = List.filled(40, 'This sentence is about a flat in Amman.').join(' ');
    final cut = speakable(long, max: 200);
    expect(cut.length, lessThanOrEqualTo(200));
    expect(cut.endsWith('.'), isTrue);
  });

  test('the voice follows the language of the reply, Jordanian Arabic first', () {
    expect(arabicShare('لقيتلك شقتين بعبدون'), greaterThan(0.9));
    expect(arabicShare('Two flats in Abdoun'), 0);
    expect(pickVoiceLanguage(['en-US', 'ar-SA', 'ar-JO'], 'ar'), 'ar-JO');
    expect(pickVoiceLanguage(['en-GB', 'ar-001'], 'ar'), 'ar-001');
    expect(pickVoiceLanguage(['en_GB', 'fr-FR'], 'en'), 'en_GB');
    expect(pickVoiceLanguage(['en-US'], 'ar'), isNull);
  });

  group('Voice conversation', () {
    testWidgets('hears a question, asks the advisor, reads the answer, then listens again', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker()..hold = Completer<void>();
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, speech, speaker));
      await step(tester);
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.listenedIn, ['en_US']);

      speech.say('find me a villa in Dabouq', done: true);
      await step(tester);
      // Asked as a spoken turn, so the advisor answers briefly, to be heard.
      expect(api.asked.single.message, 'find me a villa in Dabouq');
      expect(api.spoken, [true]);
      // Read aloud as plain words, in the reply's language, and shown too.
      expect(speaker.said.single, (text: 'I found two villas in Dabouq. Do you want something cheaper?', lang: 'en'));
      expect(find.text('Speaking…'), findsOneWidget);
      expect(find.text('find me a villa in Dabouq'), findsOneWidget);
      expect(find.text('I found two villas in Dabouq. Do you want something cheaper?'), findsOneWidget);
      // The microphone is closed while the answer is read.
      expect(speech.listenedIn.length, 1);

      speaker.hold!.complete();
      await step(tester);
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.listenedIn.length, 2);
    });

    testWidgets('speaks Arabic when asked in Arabic', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker()..hold = Completer<void>();
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, speech, speaker));
      await step(tester);
      await tester.tap(find.text('I’m speaking English'));
      await step(tester);
      expect(find.text('I’m speaking Arabic'), findsOneWidget);
      expect(speech.listenedIn.last, 'ar_JO');

      speech.say('بدي فيلا بدابوق', done: true);
      await step(tester);
      expect(speaker.said.single, (text: 'لقيتلك فيلتين بدابوق. بدك أرخص؟', lang: 'ar'));
    });

    testWidgets('a phone with no voice for the language shows the answer and waits', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker(result: SpeakResult.noVoice);
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, speech, speaker));
      await step(tester);
      speech.say('find me a villa', done: true);
      await step(tester);
      expect(find.text('I found two villas in Dabouq. Do you want something cheaper?'), findsOneWidget);
      expect(find.textContaining('no voice for this language'), findsOneWidget);
      expect(find.text('Tap the circle to speak'), findsOneWidget);
      expect(speech.listenedIn.length, 1);

      await tester.tap(find.bySemanticsLabel('Start speaking'));
      await step(tester);
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.listenedIn.length, 2);
    });

    testWidgets('tapping the orb while the answer is read interrupts it and listens', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker()..hold = Completer<void>();
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, speech, speaker));
      await step(tester);
      speech.say('find me a villa', done: true);
      await step(tester);
      expect(find.text('Speaking…'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Interrupt and speak'));
      await step(tester);
      expect(speaker.stops, greaterThan(0));
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.listenedIn.length, 2);
    });

    testWidgets('a refused microphone is explained, and silence is not an error', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final denied = FakeSpeechService(ready: false, failure: SpeechFailure.denied);
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, denied, FakeSpeaker()));
      await step(tester);
      expect(find.textContaining('Microphone access is off'), findsOneWidget);
      expect(find.text('Tap the circle to speak'), findsOneWidget);
      expect(api.asked, isEmpty);
    });

    testWidgets('silence pauses without a complaint', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final speech = FakeSpeechService();
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, speech, FakeSpeaker()));
      await step(tester);
      speech.fail(SpeechFailure.noSpeech);
      await step(tester);
      expect(find.text('Tap the circle to speak'), findsOneWidget);
      expect(find.textContaining('didn’t catch'), findsNothing);
      expect(api.asked, isEmpty);
    });

    testWidgets('an answer that failed is said to have failed, not read', (tester) async {
      final api = FakeAdvisorApi(
        (_) => [
          {'t': 'error', 'code': 'unavailable'},
        ],
      );
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker();
      await pumpScreen(tester, const VoiceConversation(), overrides: await _deps(api, speech, speaker));
      await step(tester);
      speech.say('find me a villa', done: true);
      await step(tester);
      expect(speaker.said, isEmpty);
      expect(find.textContaining('couldn’t be answered'), findsOneWidget);
    });

    testWidgets('the microphone on Property AI opens it, and the chat keeps what was said', (tester) async {
      final api = FakeAdvisorApi(_answer);
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker()..hold = Completer<void>();
      await pumpScreen(tester, const AiHubScreen(), overrides: await _deps(api, speech, speaker));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Talk to Akarat AI'));
      await step(tester);
      expect(find.byType(VoiceConversation), findsOneWidget);
      speech.say('find me a villa in Dabouq', done: true);
      await step(tester);

      await tester.tap(find.byTooltip('End voice conversation'));
      await step(tester);
      await step(tester);
      expect(find.byType(VoiceConversation), findsNothing);
      // Reading stopped with the conversation; the turn is in the chat.
      expect(speaker.stops, greaterThan(0));
      expect(find.text('find me a villa in Dabouq'), findsOneWidget);
      expect(find.textContaining('two villas', findRichText: true), findsWidgets);
    });
  });
}
