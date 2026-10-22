import 'package:akarat/app/localization/gen/app_localizations.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/features/authentication/presentation/auth_callback_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_up_screen.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/shared/repositories/account_repositories.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/harness.dart';

/// Stands in for Supabase's and Apple's side of Sign in with Apple: records
/// each call and answers with [outcome], or throws [error] when given one.
class _FakeAuth extends Fake implements AuthService {
  _FakeAuth({this.outcome = AuthOutcome.inBrowser, this.error});
  final AuthOutcome outcome;
  final Object? error;
  final calls = <String>[];

  /// Apple's one-time code for a deletion.
  static const code = 'apple-code';

  Future<T> _answer<T>(String call, T value) async {
    calls.add(call);
    if (error != null) throw error!;
    return value;
  }

  @override
  Future<AuthOutcome> signInWithApple() => _answer('signIn', outcome);

  @override
  Future<AuthOutcome> linkApple() => _answer('link', outcome);

  @override
  Future<void> unlinkApple() => _answer('unlink', null);

  @override
  Future<String?> appleCodeForDeletion() => _answer('code', code);
}

/// Records what deleting an account was asked to do.
class _FakeAccount extends Fake implements AccountRepository {
  final deleted = <String?>[];

  @override
  Future<void> deleteMyAccount({String? appleAuthorizationCode}) async => deleted.add(appleAuthorizationCode);
}

final _en = lookupAppLocalizations(const Locale('en'));

UserIdentity _identity(String provider) => UserIdentity(
  id: '$provider-id',
  userId: '22222222-2222-4222-8222-222222222222',
  identityData: const {},
  identityId: '$provider-identity',
  provider: provider,
  createdAt: '2026-09-01T00:00:00Z',
  lastSignInAt: '2026-09-01T00:00:00Z',
);

User _user(List<String> providers) => User(
  id: '22222222-2222-4222-8222-222222222222',
  appMetadata: const {},
  userMetadata: const {'full_name': 'Lina Haddad'},
  aud: 'authenticated',
  email: 'lina@example.com',
  createdAt: '2026-09-01T00:00:00Z',
  identities: [for (final p in providers) _identity(p)],
);

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(text), 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
}

Preferences _prefs(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen))).read(preferencesProvider);

/// Runs [body] as if on an iPhone.
Future<void> _onIPhone(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Profile under a real router, for the flows that navigate (deleting).
Future<void> _pumpProfile(WidgetTester tester, List<Override> overrides) => pumpRouted(
  tester,
  [
    GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
    GoRoute(
      path: Routes.home,
      builder: (_, _) => const Scaffold(body: Text('home')),
    ),
  ],
  overrides: overrides,
  initial: Routes.profile,
);

/// Deletes the account through the dialog, typing the word it asks for.
Future<void> _delete(WidgetTester tester) async {
  await _scrollTo(tester, _en.settingsDeleteAccount);
  await tester.tap(find.text(_en.settingsDeleteAccount));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), _en.deleteAccountConfirmWord);
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.actionDelete));
  await tester.pumpAndSettle();
}

void main() {
  group('Continue with Apple', () {
    testWidgets('on sign-in once Apple is switched on, and it asks Apple', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const SignInScreen(),
        overrides: [...await TestDeps().overrides(appleSignIn: true), authServiceProvider.overrideWithValue(auth)],
      );
      await _scrollTo(tester, _en.authApple);
      await tester.tap(find.text(_en.authApple));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn']);
    });

    testWidgets('not while it is switched off', (tester) async {
      await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides());
      await tester.pumpAndSettle();
      expect(find.text(_en.authApple), findsNothing);
    });

    testWidgets('on an iPhone it leads, and brings Google and Facebook with it (App Store 4.8)', (tester) async {
      await _onIPhone(() async {
        await pumpScreen(
          tester,
          const SignInScreen(),
          overrides: await TestDeps().overrides(appleSignIn: true, facebookSignIn: true),
        );
        await _scrollTo(tester, _en.authFacebook);
        final apple = tester.getTopLeft(find.text(_en.authApple)).dy;
        final google = tester.getTopLeft(find.text(_en.authGoogle)).dy;
        final facebook = tester.getTopLeft(find.text(_en.authFacebook)).dy;
        expect(apple < google && google < facebook, isTrue, reason: 'Apple first, then Google, then Facebook');
      });
    });

    testWidgets('on an iPhone without Apple there is no Google or Facebook either', (tester) async {
      await _onIPhone(() async {
        await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides(facebookSignIn: true));
        await tester.pumpAndSettle();
        expect(find.text(_en.authApple), findsNothing);
        expect(find.text(_en.authGoogle), findsNothing);
        expect(find.text(_en.authFacebook), findsNothing);
      });
    });

    testWidgets('finished on an iPhone: signed in, said so, and the page closes', (tester) async {
      await _onIPhone(() async {
        final auth = _FakeAuth(outcome: AuthOutcome.done);
        await pumpRouted(
          tester,
          [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('before')),
              routes: [GoRoute(path: 'sign-in', builder: (_, _) => const SignInScreen())],
            ),
          ],
          overrides: [...await TestDeps().overrides(appleSignIn: true), authServiceProvider.overrideWithValue(auth)],
          initial: '/sign-in',
        );
        await _scrollTo(tester, _en.authApple);
        await tester.tap(find.text(_en.authApple));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(auth.calls, ['signIn']);
        expect(find.text(_en.authWelcomeBack), findsOneWidget, reason: 'the toast, while it shows');
        await tester.pumpAndSettle();
        expect(find.text('before'), findsOneWidget, reason: 'back where the reader was');
      });
    });

    testWidgets('closing Apple’s sheet says nothing and stays put', (tester) async {
      await _onIPhone(() async {
        final auth = _FakeAuth(outcome: AuthOutcome.cancelled);
        await pumpScreen(
          tester,
          const SignInScreen(),
          overrides: [...await TestDeps().overrides(appleSignIn: true), authServiceProvider.overrideWithValue(auth)],
        );
        await _scrollTo(tester, _en.authApple);
        await tester.tap(find.text(_en.authApple));
        await tester.pumpAndSettle();
        expect(find.text(_en.authWelcomeBack), findsNothing);
        expect(find.text(_en.authAppleFailed), findsNothing);
        expect(find.byType(SignInScreen), findsOneWidget);
      });
    });

    testWidgets('Apple switched off in the project after all: said plainly', (tester) async {
      final auth = _FakeAuth(
        error: const AuthApiException('Unsupported provider: provider is not enabled', code: 'validation_failed'),
      );
      await pumpScreen(
        tester,
        const SignInScreen(),
        overrides: [...await TestDeps().overrides(appleSignIn: true), authServiceProvider.overrideWithValue(auth)],
      );
      await _scrollTo(tester, _en.authApple);
      await tester.tap(find.text(_en.authApple));
      await tester.pumpAndSettle();
      expect(find.text(_en.authAppleDisabled), findsOneWidget);
    });

    testWidgets('on sign-up too: a first Apple sign-in makes the account', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const SignUpScreen(),
        overrides: [...await TestDeps().overrides(appleSignIn: true), authServiceProvider.overrideWithValue(auth)],
      );
      await _scrollTo(tester, _en.authApple);
      await tester.tap(find.text(_en.authApple));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn']);
    });
  });

  group('Apple in Profile', () {
    testWidgets('connecting in the browser: the app remembers it asked', (tester) async {
      final auth = _FakeAuth(outcome: AuthOutcome.inBrowser);
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['email']), appleSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, _en.profileAppleConnect);
      await tester.tap(find.text(_en.profileAppleConnect));
      await tester.pumpAndSettle();
      expect(auth.calls, ['link']);
      expect(_prefs(tester, ProfileScreen).pendingLink, 'apple', reason: 'so the return can say it worked');
    });

    testWidgets('on an iPhone it connects at once and says so', (tester) async {
      await _onIPhone(() async {
        final auth = _FakeAuth(outcome: AuthOutcome.done);
        await pumpScreen(
          tester,
          const ProfileScreen(),
          overrides: [
            ...await TestDeps().overrides(user: _user(['email']), appleSignIn: true),
            authServiceProvider.overrideWithValue(auth),
          ],
        );
        await _scrollTo(tester, _en.profileAppleConnect);
        await tester.tap(find.text(_en.profileAppleConnect));
        await tester.pumpAndSettle();
        expect(find.text(_en.appleConnected), findsOneWidget);
        expect(_prefs(tester, ProfileScreen).pendingLink, isNull);
      });
    });

    testWidgets('an Apple ID on another account: said, and nothing left pending', (tester) async {
      final auth = _FakeAuth(
        error: const AuthApiException('Identity is already linked to another user', code: 'identity_already_exists'),
      );
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['email']), appleSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, _en.profileAppleConnect);
      await tester.tap(find.text(_en.profileAppleConnect));
      await tester.pumpAndSettle();
      expect(find.text(_en.appleTaken), findsOneWidget);
      expect(_prefs(tester, ProfileScreen).pendingLink, isNull);
    });

    testWidgets('a connected account can disconnect it, after confirming', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['email', 'apple']), appleSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, _en.profileAppleConnected);
      await tester.tap(find.text(_en.profileAppleConnected));
      await tester.pumpAndSettle();
      expect(find.text(_en.appleDisconnectTitle), findsOneWidget);
      expect(auth.calls, isEmpty, reason: 'nothing until confirmed');
      await tester.tap(find.text(_en.facebookDisconnect).last);
      await tester.pumpAndSettle();
      expect(auth.calls, ['unlink']);
      expect(find.text(_en.appleDisconnected), findsOneWidget);
    });

    testWidgets('an account whose only way in is Apple cannot disconnect it', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['apple'])),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, _en.profileFacebookOnly);
      await tester.tap(find.text(_en.profileFacebookOnly));
      await tester.pumpAndSettle();
      expect(auth.calls, isEmpty);
      expect(find.text(_en.appleOnlyWayIn), findsOneWidget);
    });
  });

  group('Deleting an account that signs in with Apple', () {
    testWidgets('on an iPhone, Apple confirms and its code goes with the request', (tester) async {
      await _onIPhone(() async {
        final auth = _FakeAuth();
        final account = _FakeAccount();
        await _pumpProfile(tester, [
          ...await TestDeps().overrides(user: _user(['apple'])),
          authServiceProvider.overrideWithValue(auth),
          accountRepositoryProvider.overrideWithValue(account),
        ]);
        await _scrollTo(tester, _en.settingsDeleteAccount);
        await tester.tap(find.text(_en.settingsDeleteAccount));
        await tester.pumpAndSettle();
        expect(find.text(_en.deleteAccountAppleNote), findsOneWidget, reason: 'the extra step is explained first');
        await tester.enterText(find.byType(TextField), _en.deleteAccountConfirmWord);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_en.actionDelete));
        await tester.pumpAndSettle();
        expect(auth.calls, ['code']);
        expect(account.deleted, ['apple-code']);
        expect(find.text('home'), findsOneWidget);
      });
    });

    testWidgets('closing Apple’s sheet deletes nothing, and says so', (tester) async {
      await _onIPhone(() async {
        final account = _FakeAccount();
        await _pumpProfile(tester, [
          ...await TestDeps().overrides(user: _user(['apple'])),
          authServiceProvider.overrideWithValue(_FakeAuth(error: const AppleCancelled())),
          accountRepositoryProvider.overrideWithValue(account),
        ]);
        await _delete(tester);
        expect(account.deleted, isEmpty);
        expect(find.text(_en.deleteAccountAppleCancelled), findsOneWidget);
      });
    });

    testWidgets('an account without Apple has no Apple step', (tester) async {
      await _onIPhone(() async {
        final auth = _FakeAuth();
        final account = _FakeAccount();
        await _pumpProfile(tester, [
          ...await TestDeps().overrides(user: _user(['email'])),
          authServiceProvider.overrideWithValue(auth),
          accountRepositoryProvider.overrideWithValue(account),
        ]);
        await _delete(tester);
        expect(auth.calls, isEmpty);
        expect(account.deleted, [null]);
      });
    });
  });

  group('Coming back from Apple', () {
    testWidgets('an Apple ID already on another account: said, and back to Profile', (tester) async {
      await pumpScreen(
        tester,
        const AuthCallbackScreen(
          params: {
            'error': 'server_error',
            'error_code': 'identity_already_exists',
            'error_description': 'Identity is already linked to another user',
          },
        ),
        overrides: await TestDeps().overrides(user: _user(['email']), prefs: {'akarat.pendingLink': 'apple'}),
      );
      await tester.pumpAndSettle();
      expect(find.text(_en.appleTaken), findsWidgets);
      expect(find.text(_en.authBackToProfile), findsOneWidget);
      expect(_prefs(tester, AuthCallbackScreen).pendingLink, isNull);
    });
  });

  group('Rules and wording', () {
    String say(Object e) => linkErrorMessage(_en, e, (_) => 'fallback', provider: 'apple');

    test('linking errors name Apple', () {
      expect(say(const AuthApiException('Identity is already linked to another user')), _en.appleTaken);
      expect(say(const AuthApiException('x', code: 'single_identity_not_deletable')), _en.appleOnlyWayIn);
      expect(say(const AuthApiException('Unsupported provider: provider is not enabled')), _en.authAppleDisabled);
      expect(say(const AuthApiException('x', code: 'manual_linking_disabled')), _en.facebookLinkDisabled);
      expect(say(StateError('anything else')), 'fallback');
    });

    test('a failed Apple sheet is said plainly', () {
      const failed = SignInWithAppleAuthorizationException(code: AuthorizationErrorCode.failed, message: 'failed');
      expect(appleSignInErrorMessage(_en, failed, (_) => 'fallback'), _en.authAppleFailed);
      expect(
        appleSignInErrorMessage(_en, const AuthApiException('provider is not enabled'), (_) => 'fallback'),
        _en.authAppleDisabled,
      );
    });

    test('Google and Facebook on Apple platforms only beside Sign in with Apple', () {
      expect(offersSocialLogin(TargetPlatform.android, apple: false), isTrue);
      expect(offersSocialLogin(TargetPlatform.iOS, apple: false), isFalse);
      expect(offersSocialLogin(TargetPlatform.macOS, apple: false), isFalse);
      expect(offersSocialLogin(TargetPlatform.iOS, apple: true), isTrue);
    });

    test('Apple’s own sheet on iPhone and Mac; its web page elsewhere', () {
      expect(hasNativeAppleSignIn(TargetPlatform.iOS), isTrue);
      expect(hasNativeAppleSignIn(TargetPlatform.macOS), isTrue);
      expect(hasNativeAppleSignIn(TargetPlatform.android), isFalse);
    });

    test('the Apple identity is found among an account’s ways in', () {
      expect(appleIdentity(_user(['email', 'apple']))?.provider, 'apple');
      expect(appleIdentity(_user(['facebook'])), isNull);
      expect(appleIdentity(null), isNull);
    });
  });
}
