// Visual audit of the AI tab: Property AI and Ask a Lawyer, idle and
// answering, in both languages and both themes.
//
//   flutter test test/visual/assistants_audit_test.dart --tags visual --update-goldens --run-skipped
//
// Writes test/visual/goldens/assistants/*.png for review. Tagged `visual`, so
// the normal `flutter test` run skips it (dart_test.yaml).
@Tags(['visual'])
library;

import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/ai_hub/ai_hub_screen.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:akarat/features/home/home_screen.dart';
import 'package:akarat/features/lawyer/lawyer_controller.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/assistant_fakes.dart';
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

List<StreamEvent> _lawyer(String lang) {
  final ar = lang == 'ar';
  return [
    {'t': 'conversation', 'id': 'c-1', 'title': 'Rent increase'},
    {'t': 'status', 's': 'documents'},
    {'t': 'status', 's': 'library', 'q': 'rent increase'},
    {'t': 'status', 's': 'web_search', 'q': 'Owners and Tenants Law amendments'},
    {
      't': 'urgent',
      'level': 'important',
      'text': ar ? 'ردّ كتابيًا خلال ٣٠ يومًا.' : 'Reply in writing within 30 days.',
    },
    {
      't': 'text',
      'd': ar
          ? '## الجواب المختصر\nلا يجوز للمؤجر رفع الأجرة خلال مدة العقد إلا إذا نصّ العقد على ذلك'
          : '## Short answer\nYour landlord cannot raise the rent during the lease term unless the lease allows it',
    },
    {
      't': 'cite',
      'n': [1],
    },
    {
      't': 'text',
      'd': ar
          ? '.\n\n## القانون الأردني المطبّق\nقانون المالكين والمستأجرين رقم 11 لسنة 1994 وتعديلاته، والقانون رقم 99 لسنة 2031'
          : '.\n\n## Applicable Jordanian law\nThe Owners and Tenants Law No. 11 of 1994, as amended, and Law No. 99 of 2031',
    },
    {
      't': 'cite',
      'n': [2],
    },
    {'t': 'text', 'd': '.'},
    {
      't': 'unverified',
      'refs': [ar ? 'القانون رقم 99 لسنة 2031' : 'Law No. 99 of 2031'],
    },
    {
      't': 'source',
      's': {
        'n': 1,
        'kind': 'library',
        'url': 'https://example.gov.jo/law/11-1994',
        'title': 'Owners and Tenants Law No. 11 of 1994, Article 5',
        'host': 'example.gov.jo',
        'status': 'in_force',
        'verified': '2026-10-01',
        'quote': 'The rent agreed in the lease binds both parties for its term.',
      },
    },
    {
      't': 'source',
      's': {
        'n': 2,
        'kind': 'document',
        'url': '',
        'title': 'lease.pdf',
        'host': '',
        'doc': 1,
        'page': 2,
        'quote': 'Clause 4: rent may be reviewed yearly.',
      },
    },
    {
      't': 'followups',
      'items': ar ? ['ماذا أفعل إذا رفض؟'] : ['What if the landlord refuses?'],
    },
    {'t': 'saved', 'messageId': 41},
    {'t': 'done', 'lang': lang},
  ];
}

Future<List<Override>> _deps({required String lang, bool signedIn = true, Map<String, Object?>? status}) async => [
  ...await TestDeps().overrides(user: signedIn ? fakeUser() : null),
  advisorApiProvider.overrideWithValue(FakeAdvisorApi((_) => _advisor(lang))),
  lawyerApiProvider.overrideWithValue(FakeLawyerApi(status: status, answer: (_, _) => _lawyer(lang))),
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
    testWidgets('lawyer idle $lang', (t) async {
      await render(
        t,
        'lawyer_idle_$lang',
        withNav(const AiHubScreen(mode: 'lawyer'), NavTab.ai),
        overrides: await _deps(lang: lang),
        lang: lang,
        folder: 'assistants',
      );
    });
    testWidgets('lawyer answer $lang', (t) async {
      await render(
        t,
        'lawyer_answer_$lang',
        withNav(const AiHubScreen(mode: 'lawyer'), NavTab.ai),
        overrides: await _deps(lang: lang),
        lang: lang,
        folder: 'assistants',
        interact: (t) => _ask(t, lang == 'ar' ? 'صاحب البيت بده يرفع الأجرة' : 'My landlord wants to raise the rent'),
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

  testWidgets('lawyer answer, top, dark', (t) async {
    await render(
      t,
      'lawyer_answer_dark',
      withNav(const AiHubScreen(mode: 'lawyer'), NavTab.ai),
      overrides: await _deps(lang: 'en'),
      brightness: Brightness.dark,
      folder: 'assistants',
      interact: (t) async {
        await _ask(t, 'My landlord wants to raise the rent');
        await t.pump(const Duration(milliseconds: 600));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 700));
        await t.pump(const Duration(milliseconds: 600));
      },
    );
  });

  testWidgets('lawyer signed out', (t) async {
    await render(
      t,
      'lawyer_signed_out',
      withNav(const AiHubScreen(mode: 'lawyer'), NavTab.ai),
      overrides: await _deps(
        lang: 'en',
        signedIn: false,
        status: {'ready': true, 'phase': 'open', 'signedIn': false, 'allowed': false},
      ),
      folder: 'assistants',
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
