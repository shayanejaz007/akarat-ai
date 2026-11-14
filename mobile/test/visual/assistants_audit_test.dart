// Visual audit of the AI tab: Property AI, idle and answering, in both
// languages and both themes.
//
//   flutter test test/visual/assistants_audit_test.dart --tags visual --update-goldens --run-skipped
//
// Writes test/visual/goldens/assistants/*.png for review. Tagged `visual`, so
// the normal `flutter test` run skips it (dart_test.yaml).
@Tags(['visual'])
library;

import 'dart:async';

import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/advisor/voice_conversation.dart';
import 'package:akarat/features/ai_hub/ai_hub_screen.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:akarat/features/home/home_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/assistant_fakes.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import 'render.dart';

List<StreamEvent> _advisor(String lang) {
  final ar = lang == 'ar';
  return [
    {'t': 'status', 's': 'akarat_search'},
    {'t': 'status', 's': 'web_search', 'q': 'Amman rental yields 2026'},
    {'t': 'status', 's': 'calc'},
    {
      't': 'text',
      'd': ar
          ? 'لمبلغ ١٠٠ ألف دينار، أفضل خيار هو شقة صغيرة للإيجار في خلدا أو تلاع العلي: العائد الإيجاري هناك بين ٥٪ و٦٪'
          : 'For 100,000 JOD, a small apartment to rent out in Khalda or Tla’ al-Ali is the strongest option: gross yields there run 5–6%',
    },
    {
      't': 'cite',
      'n': [1],
    },
    {
      't': 'text',
      'd': ar
          ? '.\n\n## لماذا\n- طلب ثابت من العائلات والطلاب\n- أسعار أقل من عبدون ودابوق\n'
          : '.\n\n## Why\n- Steady demand from families and students\n- Prices well below Abdoun and Dabouq\n',
    },
    {
      't': 'cards',
      'items': [
        {
          'kind': 'akarat',
          'key': 'a1',
          'id': 'p1',
          'url': 'https://akarat.ai/en/property/p1',
          'title': {'en': 'Two-bedroom apartment in Khalda', 'ar': 'شقة غرفتين في خلدا'},
          'deal': 'sale',
          'type': 'apartment',
          'price': 92000,
          'basis': 'total',
          'beds': 2,
          'baths': 2,
          'size': 135,
          'location': {'en': 'Khalda, Amman', 'ar': 'خلدا، عمّان'},
          'verified': true,
          'why': ar ? 'ضمن ميزانيتك، قريبة من الجامعات' : 'Inside your budget, close to the universities',
          'listedDays': 4,
        },
        {
          'kind': 'external',
          'key': 'e1',
          'url': 'https://www.example-portal.jo/listing/88',
          'source': {'name': 'Example Portal', 'nameAr': 'بوابة مثال', 'host': 'example-portal.jo'},
          'title': '3 bedroom apartment, Tla’ al-Ali',
          'checked': false,
          'why': ar ? 'خيار أكبر بقليل' : 'A little larger, for comparison',
        },
      ],
    },
    {
      't': 'compare',
      'columns': [
        {'key': 'p1', 'title': 'Khalda', 'source': 'akarat'},
        {'key': 'p2', 'title': 'Tla’ al-Ali', 'source': 'akarat'},
      ],
      'rows': [
        {
          'k': 'price',
          'v': [92000, 118000],
        },
        {
          'k': 'per_sqm',
          'v': [681, 702],
        },
        {
          'k': 'beds',
          'v': [2, 3],
        },
        {
          'k': 'verified',
          'v': [true, false],
        },
      ],
    },
    {
      't': 'source',
      's': {
        'n': 1,
        'url': 'https://dos.gov.jo/prices',
        'title': 'Housing price index, Q3 2026',
        'host': 'dos.gov.jo',
        'date': '2026-10-12',
      },
    },
    {
      't': 'criteria',
      'c': {
        'deal': 'sale',
        'city': 'amman',
        'areas': ['khalda'],
        'budget_max_jod': 100000,
        'bedrooms_min': 2,
      },
    },
    {
      't': 'followups',
      'items': ar
          ? ['قارن العائد مع عبدون', 'كم الضريبة عند الشراء؟']
          : ['Compare the yield with Abdoun', 'What are the purchase taxes?'],
    },
    {'t': 'notice', 'kind': 'disclaimer', 'lang': lang},
    {'t': 'done', 'transcript': 't'},
  ];
}

Future<List<Override>> _deps({required String lang, bool signedIn = true}) async => [
  ...await TestDeps().overrides(user: signedIn ? fakeUser() : null),
  advisorApiProvider.overrideWithValue(FakeAdvisorApi((_) => _advisor(lang))),
];

Future<void> _ask(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextField), q);
  await t.pump();
  await t.tap(find.byTooltip(t.element(find.byType(TextField)).l10nSend));
  await t.pump(const Duration(milliseconds: 300));
}

extension on Element {
  String get l10nSend => Localizations.localeOf(this).languageCode == 'ar' ? 'إرسال' : 'Send';
}

void main() {
  setUpAll(loadRealFonts);

  // The voice conversation while the answer is being read aloud.
  for (final lang in ['en', 'ar']) {
    testWidgets('voice conversation, speaking $lang', (t) async {
      final ar = lang == 'ar';
      final speech = FakeSpeechService();
      final speaker = FakeSpeaker()..hold = Completer<void>();
      final api = FakeAdvisorApi(
        (_) => [
          {
            't': 'text',
            'd': ar ? 'لقيتلك ثلاث شقق بعبدون ضمن ميزانيتك. أرخصها بحوالي 85 ألف دينار. بدك غرفتين ولا ثلاث؟' : 'I found three apartments in Abdoun within your budget. The cheapest is about 85 thousand dinars. Do you want two bedrooms or three?',
          },
          {'t': 'done', 'transcript': 't'},
        ],
      );
      await render(
        t,
        'voice_conversation_$lang',
        const VoiceConversation(),
        overrides: [
          ...await TestDeps(speech: speech, speaker: speaker).overrides(),
          advisorApiProvider.overrideWithValue(api),
        ],
        lang: lang,
        folder: 'assistants',
        interact: (t) async {
          speech.say(ar ? 'بدي شقة بعبدون' : 'find me an apartment in Abdoun', done: true);
        },
      );
    });
  }

  for (final lang in ['en', 'ar']) {
    testWidgets('advisor idle $lang', (t) async {
      await render(
        t,
        'advisor_idle_$lang',
        withNav(const AiHubScreen(), NavTab.ai),
        overrides: await _deps(lang: lang),
        lang: lang,
        folder: 'assistants',
      );
    });
    testWidgets('advisor answer $lang', (t) async {
      await render(
        t,
        'advisor_answer_$lang',
        withNav(const AiHubScreen(), NavTab.ai),
        overrides: await _deps(lang: lang),
        lang: lang,
        folder: 'assistants',
        interact: (t) =>
            _ask(t, lang == 'ar' ? 'معي ١٠٠ ألف دينار، وين أستثمر؟' : 'I have 100,000 JOD to invest. Where?'),
      );
    });
  }

  testWidgets('advisor answer, scrolled to the cards', (t) async {
    await render(
      t,
      'advisor_cards_en',
      withNav(const AiHubScreen(), NavTab.ai),
      overrides: await _deps(lang: 'en'),
      folder: 'assistants',
      interact: (t) async {
        await _ask(t, 'I have 100,000 JOD to invest. Where?');
        await t.pump(const Duration(milliseconds: 600));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 900));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
  });

  testWidgets('home, ask Akarat AI', (t) async {
    await render(
      t,
      'home_ask_ai',
      withNav(const HomeScreen(), NavTab.home),
      overrides: await _deps(lang: 'en'),
      folder: 'assistants',
      interact: (t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
  });

  testWidgets('advisor answer, compact, text x1.3', (t) async {
    await render(
      t,
      'advisor_compact',
      withNav(const AiHubScreen(), NavTab.ai),
      overrides: await _deps(lang: 'en'),
      device: Device.compact,
      textScale: 1.3,
      folder: 'assistants',
      interact: (t) => _ask(t, 'I have 100,000 JOD to invest. Where?'),
    );
  });
}
