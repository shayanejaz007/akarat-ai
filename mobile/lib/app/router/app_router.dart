import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/ai_search/presentation/ai_search_screen.dart';
import '../../features/authentication/presentation/auth_callback_screen.dart';
import '../../features/authentication/presentation/forgot_password_screen.dart';
import '../../features/authentication/presentation/phone_auth_screen.dart';
import '../../features/authentication/presentation/reset_password_screen.dart';
import '../../features/authentication/presentation/sign_in_screen.dart';
import '../../features/authentication/presentation/sign_up_screen.dart';
import '../../features/daily/availability_screen.dart';
import '../../features/daily/bookings_screen.dart';
import '../../features/daily/daily_screen.dart';
import '../../features/daily/notifications_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/explore/explore_screen.dart';
import '../../features/favorites/saved_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/inquiries/inquiries_screen.dart';
import '../../features/listings/presentation/listing_wizard_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/property_details/property_details_screen.dart';
import '../../features/settings/legal_screen.dart';
import '../../shared/models/listing.dart';
import '../../shared/services/preferences.dart';
import '../../shared/services/supabase_providers.dart';
import 'not_found_screen.dart';
import 'routes.dart';
import 'scaffold_with_nav.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final prefs = ref.watch(preferencesProvider);
  final authChanges = AuthChangeNotifier(client.auth);
  ref.onDispose(authChanges.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: authChanges,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final uri = state.uri;
      final path = uri.path;
      final signedIn = client.auth.currentUser != null;

      // Supabase auth redirects (email confirmation, Google, password reset)
      // carry a code or an error. The Supabase client consumes the code; the
      // callback screen waits for it and moves on.
      final q = uri.queryParameters;
      if ((path == '/' || path.isEmpty) &&
          (q.containsKey('code') || q.containsKey('error_description') || q.containsKey('error'))) {
        return Uri(path: Routes.authCallback, queryParameters: q).toString();
      }

      // The website's listing URLs, so a shared link opens in the app.
      final web = RegExp(r'^/(?:en|ar)/property/([^/]+)$').firstMatch(path);
      if (web != null) return Routes.property(web[1]!);
      if (path == '/' || path.isEmpty) return Routes.home;

      // Where the reader was going, as a place in the app. A link from
      // outside arrives whole (ai.akarat.app://open/…, https://…), and its
      // scheme and host would make it fail the in-app check on the way back.
      final here = uri.hasQuery ? '$path?${uri.query}' : path;

      // First launch: a short introduction, unless a link brought them
      // straight to a listing or back from an auth email.
      if (!prefs.onboarded &&
          path != Routes.onboarding &&
          !path.startsWith('/property/') &&
          path != Routes.authCallback &&
          path != Routes.resetPassword) {
        return Routes.withNext(Routes.onboarding, here);
      }

      if (!signedIn && Routes.isProtected(path)) return Routes.withNext(Routes.signIn, here);
      if (signedIn && Routes.isAuthPage(path)) return Routes.safeNext(q['next']) ?? Routes.profile;
      return null;
    },
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(
        path: Routes.onboarding,
        // A link that opened the app on its first launch, sign-in included,
        // is followed once the introduction is done.
        builder: (context, state) => OnboardingScreen(next: Routes.safeLink(state.uri.queryParameters['next'])),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => ScaffoldWithNav(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            FadingBranches(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.explore,
                builder: (context, state) => ExploreScreen(initialQuery: state.uri.queryParameters),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.daily, builder: (context, state) => const DailyScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.aiSearch,
                builder: (context, state) => AiSearchScreen(
                  initialQuery: state.uri.queryParameters['q'],
                  focusToken: state.uri.queryParameters['focus'],
                  voiceToken: state.uri.queryParameters['voice'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.saved,
                builder: (context, state) =>
                    SavedScreen(initialTab: state.uri.queryParameters['tab'], tabToken: state.uri.queryParameters['t']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (context, state) => const ProfileScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/property/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          return PropertyDetailsScreen(
            id: state.pathParameters['id']!,
            initial: extra is PropertyRouteArgs ? extra.listing : (extra is Listing ? extra : null),
            heroTag: extra is PropertyRouteArgs ? extra.heroTag : null,
          );
        },
      ),
      GoRoute(
        path: Routes.signIn,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => SignInScreen(next: Routes.safeNext(state.uri.queryParameters['next'])),
      ),
      GoRoute(
        path: Routes.signUp,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => SignUpScreen(next: Routes.safeNext(state.uri.queryParameters['next'])),
      ),
      GoRoute(
        path: Routes.phoneSignIn,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PhoneAuthScreen(
          kind: state.uri.queryParameters['mode'] == 'signup' ? PhoneAuthKind.signUp : PhoneAuthKind.signIn,
          next: Routes.safeNext(state.uri.queryParameters['next']),
        ),
      ),
      GoRoute(
        path: Routes.phoneLink,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PhoneAuthScreen(kind: PhoneAuthKind.link),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: Routes.authCallback,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AuthCallbackScreen(params: state.uri.queryParameters),
      ),
      GoRoute(
        path: Routes.newListing,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ListingWizardScreen(),
      ),
      GoRoute(
        path: '/listing/:id/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ListingWizardScreen(editId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/listing/:id/availability',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AvailabilityScreen(listingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.bookings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => BookingsScreen(initialTab: state.uri.queryParameters['tab']),
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.dashboard,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.inquiries,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => InquiriesScreen(initialTab: state.uri.queryParameters['tab']),
      ),
      GoRoute(
        path: '/legal/:doc',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => LegalScreen(doc: state.pathParameters['doc']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
