import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/router/app_router.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/onboarding/onboarding_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/harness.dart';

/// The app as the platform starts it from [link]: on Android and iOS the
/// whole link, scheme and all. On its first launch unless [onboarded].
Future<void> _coldStart(WidgetTester tester, String link, {bool onboarded = false}) async {
  tester.platformDispatcher.defaultRouteNameTestValue = link;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final overrides = await TestDeps().overrides(prefs: {'akarat.onboarded': onboarded});
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
}

void main() {
  group('Links inside the app', () {
    test('only pages of ours are followed', () {
      for (final ours in ['/auth/sign-in', '/property/abc?from=share', '/explore?city=amman']) {
        expect(Routes.safeLink(ours), ours);
      }
      for (final other in [
        null,
        '',
        'https://evil.example/x',
        '//evil.example/x',
        'ai.akarat.app://open/property/abc',
        'javascript:alert(1)',
        'property/abc',
      ]) {
        expect(Routes.safeLink(other), isNull, reason: '$other');
      }
    });

    test('after signing in, never back to a sign-in page', () {
      expect(Routes.safeNext('/dashboard'), '/dashboard');
      expect(Routes.safeNext('/listing/new'), '/listing/new');
      for (final other in [
        '/auth/sign-in',
        '/auth/sign-up?next=/dashboard',
        '/auth/reset-password',
        '//evil.example',
      ]) {
        expect(Routes.safeNext(other), isNull, reason: other);
      }
    });
  });

  group('A link that opens the app on its first launch', () {
    testWidgets('to sign in: the introduction, then sign-in', (tester) async {
      await _coldStart(tester, 'ai.akarat.app://open/auth/sign-in');
      expect(find.byType(OnboardingScreen), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('carrying a link to another site: sign-in, which returns nowhere else', (tester) async {
      await _coldStart(
        tester,
        'ai.akarat.app://open/auth/sign-in?next=${Uri.encodeComponent('https://evil.example/')}',
      );
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(tester.widget<SignInScreen>(find.byType(SignInScreen)).next, isNull);
    });

    testWidgets('to a listing on the website: the listing, before any introduction', (tester) async {
      await _coldStart(tester, 'https://akarat.ai/en/property/abc');
      expect(find.byType(PropertyDetailsScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });
  });

  testWidgets('a link to a page that needs an account returns there after sign-in', (tester) async {
    await _coldStart(tester, 'ai.akarat.app://open/dashboard', onboarded: true);
    expect(tester.widget<SignInScreen>(find.byType(SignInScreen)).next, '/dashboard');
  });
}
