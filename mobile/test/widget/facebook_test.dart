import 'package:akarat/app/localization/gen/app_localizations.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/features/authentication/presentation/auth_callback_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_up_screen.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/harness.dart';

/// Stands in for Supabase's Facebook sign-in and linking: records each call
/// and answers with [error] when given one.
class _FakeAuth extends Fake implements AuthService {
  _FakeAuth({this.error});
  final Object? error;
  final calls = <String>[];

  @override
  Future<void> signInWithFacebook() async {
    calls.add('signIn');
    if (error != null) throw error!;
  }

  @override
  Future<void> linkFacebook() async {
    calls.add('link');
    if (error != null) throw error!;
  }

  @override
  Future<void> unlinkFacebook() async {
    calls.add('unlink');
    if (error != null) throw error!;
  }
}

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
  // Built is not on screen: the list builds a little beyond its edge.
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
}

Preferences _prefs(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen))).read(preferencesProvider);

void main() {
  group('Continue with Facebook', () {
    testWidgets('on sign-in once Facebook is switched on, and it opens Facebook', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const SignInScreen(),
        overrides: [...await TestDeps().overrides(facebookSignIn: true), authServiceProvider.overrideWithValue(auth)],
      );
      await _scrollTo(tester, 'Continue with Facebook');
      await tester.tap(find.text('Continue with Facebook'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn']);
    });

    testWidgets('not while it is switched off', (tester) async {
      await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides());
      await tester.pumpAndSettle();
      expect(find.text('Continue with Facebook'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('never on iPhone, where Apple would require Sign in with Apple beside it', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides(facebookSignIn: true));
        await tester.pumpAndSettle();
        expect(find.text('Continue with Facebook'), findsNothing);
        expect(find.text('Continue with Google'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Facebook switched off in the project after all: said plainly', (tester) async {
      final auth = _FakeAuth(
        error: const AuthApiException('Unsupported provider: provider is not enabled', code: 'validation_failed'),
      );
      await pumpScreen(
        tester,
        const SignInScreen(),
        overrides: [...await TestDeps().overrides(facebookSignIn: true), authServiceProvider.overrideWithValue(auth)],
      );
      await _scrollTo(tester, 'Continue with Facebook');
      await tester.tap(find.text('Continue with Facebook'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Facebook sign-in isn’t switched on yet'), findsOneWidget);
    });

    testWidgets('on sign-up too: a first Facebook sign-in makes the account', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const SignUpScreen(),
        overrides: [...await TestDeps().overrides(facebookSignIn: true), authServiceProvider.overrideWithValue(auth)],
      );
      await _scrollTo(tester, 'Continue with Facebook');
      await tester.tap(find.text('Continue with Facebook'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['signIn']);
    });
  });

  group('Facebook in Profile', () {
    testWidgets('an account without it can connect it, and the app remembers it asked', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['email']), facebookSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, 'Connect it to sign in with Facebook');
      await tester.tap(find.text('Connect it to sign in with Facebook'));
      await tester.pumpAndSettle();
      expect(auth.calls, ['link']);
      expect(_prefs(tester, ProfileScreen).pendingLink, 'facebook', reason: 'so the return can say it worked');
    });

    testWidgets('connecting switched off in Supabase: said plainly, and nothing is left pending', (tester) async {
      final auth = _FakeAuth(
        error: const AuthApiException('Manual linking is disabled', code: 'manual_linking_disabled'),
      );
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['email']), facebookSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, 'Connect it to sign in with Facebook');
      await tester.tap(find.text('Connect it to sign in with Facebook'));
      await tester.pumpAndSettle();
      expect(find.text('Connecting accounts isn’t switched on yet. Try again later.'), findsOneWidget);
      expect(_prefs(tester, ProfileScreen).pendingLink, isNull);
    });

    testWidgets('a connected account can disconnect it, after confirming', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['email', 'facebook']), facebookSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, 'Connected: you can sign in with Facebook');
      await tester.tap(find.text('Connected: you can sign in with Facebook'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect Facebook?'), findsOneWidget);
      expect(auth.calls, isEmpty, reason: 'nothing until confirmed');
      await tester.tap(find.text('Disconnect').last);
      await tester.pumpAndSettle();
      expect(auth.calls, ['unlink']);
      expect(find.text('Facebook disconnected'), findsOneWidget);
    });

    testWidgets('an account whose only way in is Facebook cannot disconnect it', (tester) async {
      final auth = _FakeAuth();
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ...await TestDeps().overrides(user: _user(['facebook']), facebookSignIn: true),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      await _scrollTo(tester, 'Connected: the way this account signs in');
      expect(find.text('Disconnect'), findsNothing);
      await tester.tap(find.text('Connected: the way this account signs in'));
      await tester.pumpAndSettle();
      expect(auth.calls, isEmpty);
      expect(find.textContaining('Add a phone number first'), findsOneWidget);
    });

    testWidgets('a connected account still shows it if Facebook is later switched off', (tester) async {
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: await TestDeps().overrides(user: _user(['email', 'facebook'])),
      );
      await _scrollTo(tester, 'Connected: you can sign in with Facebook');
      expect(find.text('Facebook'), findsOneWidget);
    });
  });

  group('Coming back from Facebook', () {
    testWidgets('a Facebook account already on another account: said, and back to Profile', (tester) async {
      await pumpScreen(
        tester,
        const AuthCallbackScreen(
          params: {
            'error': 'server_error',
            'error_code': 'identity_already_exists',
            'error_description': 'Identity is already linked to another user',
          },
        ),
        overrides: await TestDeps().overrides(user: _user(['email']), prefs: {'akarat.pendingLink': 'facebook'}),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('already belongs to another Akarat.ai account'), findsWidgets);
      expect(find.text('Back to profile'), findsOneWidget);
      expect(_prefs(tester, AuthCallbackScreen).pendingLink, isNull);
    });

    testWidgets('cancelled at Facebook: said as a cancellation, not an expired link', (tester) async {
      await pumpScreen(
        tester,
        const AuthCallbackScreen(params: {'error': 'access_denied', 'error_description': 'User denied'}),
        overrides: await TestDeps().overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign-in was cancelled. Nothing was changed.'), findsWidgets);
      expect(find.text('Sign in'), findsOneWidget, reason: 'signed out: on to sign-in');
    });
  });

  group('Wording of linking errors', () {
    final l = lookupAppLocalizations(const Locale('en'));
    String say(Object e) => linkErrorMessage(l, e, (_) => 'fallback');

    test('each failure says what happened', () {
      expect(
        say(const AuthApiException('Manual linking is disabled', code: 'manual_linking_disabled')),
        l.facebookLinkDisabled,
      );
      expect(
        say(const AuthApiException('Identity is already linked to another user', code: 'identity_already_exists')),
        l.facebookTaken,
      );
      expect(
        say(
          const AuthApiException(
            'User must have at least 1 identity after unlinking',
            code: 'single_identity_not_deletable',
          ),
        ),
        l.facebookOnlyWayIn,
      );
      expect(say(const AuthApiException('Unsupported provider: provider is not enabled')), l.authFacebookDisabled);
      expect(say(StateError('anything else')), 'fallback');
    });

    test('the Facebook identity is found among an account\'s ways in', () {
      expect(facebookIdentity(_user(['email', 'facebook']))?.provider, 'facebook');
      expect(facebookIdentity(_user(['email'])), isNull);
      expect(facebookIdentity(null), isNull);
    });
  });
}
