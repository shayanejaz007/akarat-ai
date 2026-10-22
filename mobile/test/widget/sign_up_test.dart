import 'package:akarat/app/router/routes.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_up_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/harness.dart';

/// Answers sign-up as the project would: with a session, or without one
/// when the address must be confirmed first.
class _FakeAuth extends Fake implements AuthService {
  _FakeAuth({required this.session});
  final bool session;
  final created = <String>[];
  Map<String, Object> extra = const {};

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
    required String locale,
    Map<String, Object> extra = const {},
  }) async {
    created.add(email);
    this.extra = extra;
    return session;
  }

  @override
  Future<void> signIn(String email, String password) async => created.add(email);
}

/// Where the reader was before opening an auth page, as the tab bar's Log in
/// button and the other entry points open it: pushed on top.
List<RouteBase> _routes(String authPath, Widget page) => [
  GoRoute(
    path: '/',
    builder: (context, _) => Scaffold(
      body: Center(
        child: TextButton(onPressed: () => context.push(authPath), child: const Text('Where I was')),
      ),
    ),
  ),
  GoRoute(path: authPath, builder: (_, _) => page),
  GoRoute(
    path: Routes.home,
    builder: (_, _) => const Scaffold(body: Text('Home')),
  ),
];

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Lina Haddad');
  await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'lina@example.com');
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create account'));
  await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
}

void main() {
  testWidgets('with email confirmation on, a full page says what to do next', (tester) async {
    final auth = _FakeAuth(session: false);
    await pumpScreen(
      tester,
      const SignUpScreen(),
      overrides: [...await TestDeps().overrides(), authServiceProvider.overrideWithValue(auth)],
    );
    await _fill(tester);
    await tester.pumpAndSettle();
    expect(auth.created, ['lina@example.com']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('lina@example.com'), findsOneWidget);
    expect(find.text('I’ve confirmed — sign in'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsNothing, reason: 'the form gives way');
  });

  testWidgets('signed straight in: confirmed, on to Home, and owed the welcome tour', (tester) async {
    final auth = _FakeAuth(session: true);
    await pumpRouted(
      tester,
      _routes('/sign-up', const SignUpScreen()),
      // A device that has not shown the tour yet.
      overrides: [
        ...await TestDeps().overrides(prefs: {'akarat.tour.explore': false}),
        authServiceProvider.overrideWithValue(auth),
      ],
    );
    await tester.tap(find.text('Where I was'));
    await tester.pumpAndSettle();
    await _fill(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Welcome, Lina Haddad. Your account is ready.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SignUpScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget, reason: 'a new account starts on Home, where its tour begins');
    expect(auth.extra['tour_pending'], isTrue, reason: 'the account is owed its welcome tour');
  });

  testWidgets('a guest who already took the tour is still welcomed, and what was seen comes along', (tester) async {
    final auth = _FakeAuth(session: true);
    await pumpRouted(
      tester,
      _routes('/sign-up', const SignUpScreen()),
      overrides: [...await TestDeps().overrides(), authServiceProvider.overrideWithValue(auth)],
    );
    await tester.tap(find.text('Where I was'));
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.pumpAndSettle();
    expect(auth.extra['tour_pending'], isTrue, reason: 'every new account is welcomed (briefly, here)');
    expect(auth.extra['tours_done'], containsAll(['explore', 'map']), reason: 'what was seen travels with the account');
  });

  testWidgets('signing in from the Log in button returns to where the reader was', (tester) async {
    final auth = _FakeAuth(session: true);
    await pumpRouted(
      tester,
      _routes('/sign-in', const SignInScreen()),
      overrides: [...await TestDeps().overrides(), authServiceProvider.overrideWithValue(auth)],
    );
    await tester.tap(find.text('Where I was'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'test@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(auth.created, ['test@example.com']);
    expect(find.text('Signed in'), findsOneWidget, reason: 'said on screen');
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsNothing, reason: 'the page does not linger after signing in');
    expect(find.text('Where I was'), findsOneWidget);
  });
}
