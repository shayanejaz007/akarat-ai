import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/router/app_router.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/ai_hub/ai_hub_screen.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:akarat/features/assistant/composer.dart';
import 'package:akarat/features/lawyer/lawyer_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/assistant_fakes.dart';
import '../support/harness.dart';

List<StreamEvent> _villas(String _) => [
  {'t': 'status', 's': 'akarat_search'},
  {'t': 'text', 'd': 'Two villas fit your budget'},
  {
    't': 'cite',
    'n': [1],
  },
  {'t': 'text', 'd': '.'},
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
        'beds': 5,
        'location': {'en': 'Dabouq, Amman', 'ar': 'دابوق، عمّان'},
        'verified': true,
        'why': 'Inside your budget, close to the schools',
        'listedDays': 3,
      },
    ],
  },
  {
    't': 'source',
    's': {'n': 1, 'url': 'https://dos.gov.jo/prices', 'title': 'Housing prices 2026', 'host': 'dos.gov.jo'},
  },
  {
    't': 'followups',
    'items': ['Compare the two villas'],
  },
  {'t': 'notice', 'kind': 'disclaimer', 'lang': 'en'},
  {'t': 'done', 'transcript': 't1'},
];

Future<List<Override>> _deps({FakeAdvisorApi? advisor, FakeLawyerApi? lawyer, bool signedIn = false}) async => [
  ...await TestDeps().overrides(user: signedIn ? fakeUser() : null),
  advisorApiProvider.overrideWithValue(advisor ?? FakeAdvisorApi(_villas)),
  lawyerApiProvider.overrideWithValue(lawyer ?? FakeLawyerApi()),
];

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the AI tab opens on Property AI, and Ask a Lawyer is one tap away', (tester) async {
    final lawyer = FakeLawyerApi(status: {'ready': true, 'phase': 'open', 'signedIn': false, 'allowed': false});
    await pumpScreen(tester, const AiHubScreen(), overrides: await _deps(lawyer: lawyer));
    await tester.pumpAndSettle();
    expect(find.text('Find your next property with AI.'), findsOneWidget);
    expect(find.byTooltip('Plain search'), findsOneWidget);

    await tester.tap(find.text('Ask a Lawyer'));
    await tester.pumpAndSettle();
    expect(find.text('Ask a Lawyer.'), findsOneWidget);
    expect(find.text('Sign in to ask. Your conversations and documents stay private to your account.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.byTooltip('History'), findsNothing, reason: 'no history before signing in');
  });

  testWidgets('Property AI answers with the listings it found, its sources and what to ask next', (tester) async {
    final advisor = FakeAdvisorApi(_villas);
    await pumpScreen(tester, const AiHubScreen(), overrides: await _deps(advisor: advisor));
    await tester.pumpAndSettle();
    await _ask(tester, 'Villas in Dabouq under 500,000');

    // The newest answer is in view; the question is above it.
    expect(find.textContaining('Two villas fit your budget', findRichText: true), findsOneWidget);
    expect(find.text('Villa in Dabouq'), findsOneWidget);
    expect(find.text('Inside your budget, close to the schools'), findsOneWidget);
    expect(find.text('Housing prices 2026'), findsOneWidget);
    expect(
      find.textContaining('Property markets involve risk'),
      findsOneWidget,
      reason: 'the risk note the server asked for',
    );

    await tester.scrollUntilVisible(
      find.text('Compare the two villas'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Compare the two villas'));
    await tester.pumpAndSettle();
    expect(advisor.asked.map((a) => a.message), ['Villas in Dabouq under 500,000', 'Compare the two villas']);
    expect(advisor.asked.last.transcript, 't1');
    await tester.scrollUntilVisible(
      find.text('Villas in Dabouq under 500,000'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Villas in Dabouq under 500,000'), findsOneWidget, reason: 'the question, as asked');
  });

  testWidgets("when the advisor can't answer, the plain search takes the question", (tester) async {
    final advisor = FakeAdvisorApi(
      (_) => [
        {'t': 'error', 'code': 'quota'},
      ],
    );
    await pumpRouted(tester, [
      GoRoute(path: '/', builder: (_, _) => const AiHubScreen()),
      GoRoute(
        path: Routes.plainSearch,
        builder: (_, state) => Scaffold(body: Text('Plain search: ${state.uri.queryParameters['q']}')),
      ),
    ], overrides: await _deps(advisor: advisor));
    await _ask(tester, 'flat in Khalda');
    expect(find.textContaining('reached today’s limit for the AI advisor'), findsOneWidget);
    await tester.tap(find.text('Search the listings instead'));
    await tester.pumpAndSettle();
    expect(find.text('Plain search: flat in Khalda'), findsOneWidget);
  });

  testWidgets('Ask a Lawyer answers in sections, with its sources, the notice and what to do next', (tester) async {
    final lawyer = FakeLawyerApi();
    await pumpScreen(
      tester,
      const AiHubScreen(mode: 'lawyer'),
      overrides: await _deps(lawyer: lawyer, signedIn: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ask a Lawyer.'), findsOneWidget);
    expect(find.text('Can a foreigner purchase property in Amman?'), findsOneWidget, reason: 'suggested questions');
    expect(find.byTooltip('History'), findsOneWidget);

    await _ask(tester, 'My landlord wants to raise the rent');
    expect(find.text('Short answer'), findsOneWidget, reason: 'a section heading');
    expect(find.textContaining('cannot raise the rent mid-term', findRichText: true), findsOneWidget);
    expect(find.text('Owners and Tenants Law, Article 5'), findsOneWidget);
    expect(find.text('Verified law · in force'), findsOneWidget);
    expect(find.textContaining('not a substitute for professional legal advice'), findsOneWidget);
    expect(find.text('Share summary'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Report a problem'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Report a problem'));
    await tester.pumpAndSettle();
    expect(find.text('What was wrong with this answer?'), findsOneWidget);
    await tester.tap(find.text('Wrong article or citation'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(lawyer.reports.single.kind, 'wrong_citation');
    expect(lawyer.reports.single.messageId, 41);
    expect(find.text('Reported'), findsOneWidget);
  });

  testWidgets('references that could not be verified are listed, and an urgent warning comes first', (tester) async {
    final lawyer = FakeLawyerApi(
      answer: (_, _) => [
        {'t': 'conversation', 'id': 'c-2', 'title': 'Eviction'},
        {'t': 'urgent', 'level': 'urgent', 'text': 'You have 7 days to object.'},
        {'t': 'text', 'd': 'Under Law No. 99 of 2031 you may object.'},
        {
          't': 'unverified',
          'refs': ['Law No. 99 of 2031'],
        },
        {'t': 'saved', 'messageId': 7},
        {'t': 'done', 'lang': 'en'},
      ],
    );
    await pumpScreen(
      tester,
      const AiHubScreen(mode: 'lawyer'),
      overrides: await _deps(lawyer: lawyer, signedIn: true),
    );
    await tester.pumpAndSettle();
    await _ask(tester, 'I got an eviction notice');
    expect(find.text('Urgent. You have 7 days to object.'), findsOneWidget);
    expect(find.text('References that couldn’t be verified'), findsOneWidget);
    expect(find.text('• Law No. 99 of 2031'), findsOneWidget);
  });

  testWidgets('before launch, only reviewers may ask: everyone else is told why and the box is locked', (tester) async {
    final lawyer = FakeLawyerApi(status: {'ready': true, 'phase': 'review', 'signedIn': true, 'allowed': false});
    await pumpScreen(
      tester,
      const AiHubScreen(mode: 'lawyer'),
      overrides: await _deps(lawyer: lawyer, signedIn: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Ask a Lawyer is being reviewed by licensed Jordanian lawyers before it opens to everyone.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('both assistants keep their conversations while the reader switches between them', (tester) async {
    await pumpScreen(tester, const AiHubScreen(), overrides: await _deps(signedIn: true));
    await tester.pumpAndSettle();
    await _ask(tester, 'Villas in Dabouq');
    await tester.tap(find.text('Ask a Lawyer'));
    await tester.pumpAndSettle();
    await _ask(tester, 'Is a verbal lease valid?');
    await tester.tap(find.text('Property AI'));
    await tester.pumpAndSettle();
    expect(find.text('Villa in Dabouq'), findsOneWidget);
    await tester.tap(find.text('Ask a Lawyer'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Is a verbal lease valid?'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Is a verbal lease valid?'), findsOneWidget);
  });

  testWidgets('in the app, the message box sits right on the keyboard, not a keyboard above it', (tester) async {
    tester.platformDispatcher.defaultRouteNameTestValue = Routes.aiSearch;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final overrides = await _deps();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        retry: (_, _) => null,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            theme: AppTheme.build(brightness: Brightness.light, lang: 'en'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AiHubScreen), findsOneWidget);

    // A 300-point keyboard comes up.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byType(AssistantComposer)).dy, moreOrLessEquals(844 - 300, epsilon: 1));
  });
}
