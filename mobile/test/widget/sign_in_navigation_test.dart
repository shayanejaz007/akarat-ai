import 'dart:async';
import 'dart:convert';

import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/router/app_router.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/harness.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// Signs in the way Supabase does: a session lands on the client and an auth
/// event goes out, which the router hears at the same moment the screen does.
class _SigningIn extends Fake implements AuthService {
  _SigningIn(this._client, {this.newAccount = false});
  final SupabaseClient _client;

  /// A session for an account made just now, rather than a returning one.
  final bool newAccount;

  Future<void> _session() async {
    final now = DateTime.now().toUtc();
    final created = newAccount ? now : DateTime.utc(2026, 9, 1);
    await _client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'test-refresh-token',
        'user': {
          'id': '22222222-2222-4222-8222-222222222222',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'lina@example.com',
          'app_metadata': {'provider': 'email'},
          'user_metadata': {'full_name': 'Lina Haddad'},
          'created_at': created.toIso8601String(),
          'last_sign_in_at': now.toIso8601String(),
        },
      }),
    );
  }

  @override
  Future<void> signIn(String email, String password) => _session();

  @override
  Future<AuthOutcome> signInWithApple() async {
    await _session();
    return AuthOutcome.done;
  }
}

/// The whole app, onboarded and signed out, on [client].
Future<GoRouter> _app(WidgetTester tester, SupabaseClient client, {bool newAccount = false}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final overrides = await TestDeps().overrides(
    prefs: {...TestDeps.seen, 'akarat.onboarded': true},
    auth: client,
    appleSignIn: true,
  );
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        authServiceProvider.overrideWithValue(_SigningIn(client, newAccount: newAccount)),
      ],
      retry: (_, _) => null,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: router = ref.watch(routerProvider),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          theme: AppTheme.build(brightness: Brightness.light, lang: 'en'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Offline: the only request a test makes, signing out, is answered as
/// Supabase would.
SupabaseClient _client() => SupabaseClient(
  'https://supabase.invalid',
  'test-publishable-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient((req) async => http.Response('', 204, request: req)),
);

String _where(GoRouter router) => router.routerDelegate.currentConfiguration.uri.toString();

Future<void> _signInByEmail(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'lina@example.com');
  await tester.enterText(find.byType(TextFormField).at(1), 'correct horse battery');
  await tester.tap(find.widgetWithText(FilledButton, _en.actionSignIn).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('email: opened over Home, signing in goes back to Home', (tester) async {
    final client = _client();
    final router = await _app(tester, client);
    unawaited(router.push(Routes.signIn));
    await tester.pumpAndSettle();
    await _signInByEmail(tester);
    expect(find.byType(SignInScreen), findsNothing, reason: 'the sign-in page has gone (at ${_where(router)})');
    expect(_where(router), Routes.home);
  });

  testWidgets('email: sent to sign in on the way somewhere, signing in arrives there', (tester) async {
    final client = _client();
    final router = await _app(tester, client);
    router.go(Routes.dashboard);
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    await _signInByEmail(tester);
    expect(find.byType(SignInScreen), findsNothing, reason: 'at ${_where(router)}');
    expect(_where(router), Routes.dashboard);
  });

  testWidgets('a session that ends still sends a protected screen to sign-in', (tester) async {
    final client = _client();
    final router = await _app(tester, client);
    unawaited(router.push(Routes.signIn));
    await tester.pumpAndSettle();
    await _signInByEmail(tester);
    router.go(Routes.dashboard);
    await tester.pumpAndSettle();
    expect(_where(router), Routes.dashboard);
    await client.auth.signOut(scope: SignOutScope.local);
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(_where(router), Routes.withNext(Routes.signIn, Routes.dashboard));
  });

  testWidgets('Apple on an iPhone: signing in leaves the sign-in page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final client = _client();
      final router = await _app(tester, client);
      unawaited(router.push(Routes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.authApple));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing, reason: 'at ${_where(router)}');
      expect(_where(router), Routes.home);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Apple on an iPhone, a brand-new account: on to Home for its welcome', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final client = _client();
      final router = await _app(tester, client, newAccount: true);
      router.go(Routes.profile);
      await tester.pumpAndSettle();
      unawaited(router.push(Routes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.authApple));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing, reason: 'at ${_where(router)}');
      expect(_where(router), Routes.home);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
