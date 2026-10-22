import 'package:akarat/features/ai_search/presentation/ai_search_screen.dart';
import 'package:akarat/features/ai_search/voice/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The listening orb breathes until listening ends, so the screen never
/// "settles" while it listens: step time forward instead.
Future<void> step(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('Jordanian Arabic is preferred for Arabic, then other Levantine variants', () {
    expect(pickSpeechLocale(['en_US', 'ar_SA', 'ar_JO'], 'ar'), 'ar_JO');
    expect(pickSpeechLocale(['en-US', 'ar-LB', 'ar-EG'], 'ar'), 'ar-LB');
    expect(pickSpeechLocale(['en_GB', 'ar_EG'], 'en'), 'en_GB');
    expect(pickSpeechLocale(['en_US'], 'ar'), isNull);
  });

  group('Voice search', () {
    Future<FakeSearchRepository> open(WidgetTester tester, FakeSpeechService speech) async {
      final repo = FakeSearchRepository((_) => outcomeOf(const []));
      await pumpScreen(
        tester,
        const AiSearchScreen(voiceToken: '1'),
        overrides: await TestDeps(search: repo, speech: speech).overrides(),
      );
      await step(tester);
      return repo;
    }

    testWidgets('listens, shows the words live, lets them be checked, then searches', (tester) async {
      final speech = FakeSpeechService();
      final repo = await open(tester, speech);
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.listenedIn.single, 'en_US', reason: 'the interface language first');

      speech
        ..level(-2)
        ..level(8)
        ..say('three bedroom apartment in Abdoun');
      await tester.pump();
      expect(find.text('three bedroom apartment in Abdoun'), findsOneWidget, reason: 'live transcript');

      speech.say('three bedroom apartment in Abdoun under eighty thousand JOD', done: true);
      await tester.pumpAndSettle();
      expect(find.text('Is this right?'), findsOneWidget);
      // What will be searched, read before searching.
      expect(find.text('Abdoun'), findsOneWidget);
      expect(find.text('3+ bedrooms'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      final asked = repo.calls.single;
      expect(asked.hood, 'abdoun');
      expect(asked.beds, 3);
      expect(asked.budgetMax, 80000);
    });

    testWidgets('a refused microphone says so and offers typing', (tester) async {
      final speech = FakeSpeechService(ready: false, failure: SpeechFailure.denied);
      await open(tester, speech);
      expect(find.textContaining('Microphone access is off'), findsOneWidget);
      expect(find.text('Speak again'), findsNothing, reason: 'retrying cannot help');
      await tester.tap(find.text('Type instead'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Microphone access is off'), findsNothing);
    });

    testWidgets('switching to Arabic listens in Jordanian Arabic', (tester) async {
      final speech = FakeSpeechService();
      await open(tester, speech);
      await tester.tap(find.text('العربية'));
      await step(tester);
      expect(speech.listenedIn.last, 'ar_JO');
    });

    testWidgets('no Arabic recogniser on the device is said plainly', (tester) async {
      final speech = FakeSpeechService(locales: const ['en_US']);
      await open(tester, speech);
      await tester.tap(find.text('العربية'));
      await step(tester);
      expect(find.textContaining('recognise speech in this language'), findsOneWidget);
    });

    testWidgets('silence is not a search', (tester) async {
      final speech = FakeSpeechService();
      await open(tester, speech);
      speech.fail(SpeechFailure.noSpeech);
      await step(tester);
      expect(find.text('I didn’t catch that.'), findsOneWidget);
      expect(find.text('Speak again'), findsOneWidget);
    });
  });

  group('AI Search conversation', () {
    testWidgets('no match: says so, then offers one-step-looser searches that really run', (tester) async {
      final repo = FakeSearchRepository((_) => outcomeOf(const []));
      await pumpScreen(tester, const AiSearchScreen(), overrides: await TestDeps(search: repo).overrides());
      await tester.enterText(find.byType(TextField), 'villa for sale in Abdoun under 100k');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await step(tester);
      await tester.pumpAndSettle();
      expect(find.text('Nothing in our inventory matches that yet.'), findsOneWidget);
      expect(find.text('Nothing on Akarat.ai matches all of that yet.'), findsNothing, reason: 'said once, not twice');
      expect(find.text('Try instead'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('All of Amman'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('All of Amman'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.hood, isNull);
      expect(repo.calls.last.city, 'amman');
      expect(repo.calls.last.type, 'villa', reason: 'only the area was loosened');
    });

    testWidgets('a missing budget is offered as a quick choice', (tester) async {
      final repo = FakeSearchRepository((_) => outcomeOf(const []));
      await pumpScreen(tester, const AiSearchScreen(), overrides: await TestDeps(search: repo).overrides());
      await tester.enterText(find.byType(TextField), 'apartment for sale in Khalda');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      // The suggestions scroll sideways; bring this one into view first.
      await tester.ensureVisible(find.text('Under 200K JOD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Under 200K JOD'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.budgetMax, 200000);
    });
  });
}
