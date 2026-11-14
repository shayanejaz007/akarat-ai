import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/router/app_router.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/advisor/advisor_controller.dart';
import 'package:akarat/features/ai_hub/ai_hub_screen.dart';
import 'package:akarat/features/assistant/assistant_stream.dart';
import 'package:akarat/features/assistant/composer.dart';
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

Future<List<Override>> _deps({FakeAdvisorApi? advisor, bool signedIn = false}) async => [
  ...await TestDeps().overrides(user: signedIn ? fakeUser() : null),
  advisorApiProvider.overrideWithValue(advisor ?? FakeAdvisorApi(_villas)),
];

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the AI tab opens on Property AI, with the plain search one tap away', (tester) async {
    await pumpScreen(tester, const AiHubScreen(), overrides: await _deps());
    await tester.pumpAndSettle();
    expect(find.text('Find your next property with AI.'), findsOneWidget);
    expect(find.byTooltip('Plain search'), findsOneWidget);
    expect(find.text('Ask a Lawyer'), findsNothing, reason: 'Ask a Lawyer has been taken out of the app');
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
