import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/core/widgets/map_layer.dart';
import 'package:akarat/core/widgets/maps.dart';
import 'package:akarat/features/ai_search/data/search_repository.dart';
import 'package:akarat/features/ai_search/voice/speech_service.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/shared/repositories/account_repositories.dart';
import 'package:akarat/shared/repositories/favorites_repository.dart';
import 'package:akarat/shared/repositories/listings_repository.dart';
import 'package:akarat/shared/repositories/media_repository.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:akarat/shared/services/supabase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

/// Everything a screen might reach, faked. No test talks to Supabase or
/// Vercel: the client below points at a reserved, unresolvable host and is
/// only there so providers that read `auth.currentUser` get null.
class TestDeps {
  TestDeps({
    FakeListingsRepository? listings,
    FakeFavoritesRepository? favorites,
    this.search,
    FakeInquiriesRepository? inquiries,
    FakeMediaRepository? media,
    FakeSavedSearchesRepository? savedSearches,
    FakeProfileRepository? profile,
    this.speech,
  }) : savedSearches = savedSearches ?? FakeSavedSearchesRepository(),
       profile = profile ?? FakeProfileRepository(),
       listings = listings ?? FakeListingsRepository(),
       favorites = favorites ?? FakeFavoritesRepository(available: false),
       inquiries = inquiries ?? FakeInquiriesRepository(),
       media = media ?? FakeMediaRepository();

  final FakeListingsRepository listings;
  final FakeFavoritesRepository favorites;
  final FakeSearchRepository? search;
  final FakeInquiriesRepository inquiries;
  final FakeMediaRepository media;
  final FakeSavedSearchesRepository savedSearches;
  final FakeProfileRepository profile;
  final FakeSpeechService? speech;

  static final client = SupabaseClient(
    'https://supabase.invalid',
    'test-publishable-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  /// Tours count as seen unless a test says otherwise, so they never cover
  /// the screen under test.
  static const seen = {
    'akarat.onboarded': true,
    'akarat.tour.explore': true,
    'akarat.tour.map': true,
    'akarat.tour.listing': true,
    'akarat.tour.property': true,
  };

  /// [googleMaps]: as if a Maps key were built in. Pair it with a
  /// FakeGoogleMapsPlatform (test/support/fake_google_maps.dart).
  /// [phoneSignIn], [facebookSignIn], [appleSignIn]: as if the project had
  /// them switched on.
  /// [auth]: a client the test signs in on; the signed-in user then follows
  /// its auth events, as in the app, instead of being fixed to [user].
  Future<List<Override>> overrides({
    User? user,
    SupabaseClient? auth,
    Map<String, Object> prefs = seen,
    bool googleMaps = false,
    bool phoneSignIn = false,
    bool facebookSignIn = false,
    bool appleSignIn = false,
  }) async {
    SharedPreferences.setMockInitialValues({...seen, ...prefs});
    final p = await SharedPreferences.getInstance();
    return [
      preferencesProvider.overrideWithValue(Preferences(p)),
      supabaseClientProvider.overrideWithValue(auth ?? client),
      if (auth == null) currentUserProvider.overrideWithValue(user),
      listingsRepositoryProvider.overrideWithValue(listings),
      favoritesRepositoryProvider.overrideWithValue(favorites),
      inquiriesRepositoryProvider.overrideWithValue(inquiries),
      mediaRepositoryProvider.overrideWithValue(media),
      savedSearchesRepositoryProvider.overrideWithValue(savedSearches),
      profileRepositoryProvider.overrideWithValue(profile),
      if (search != null) searchRepositoryProvider.overrideWithValue(search!),
      speechServiceProvider.overrideWithValue(speech ?? FakeSpeechService()),
      // No tile requests in tests: maps draw their pins on a plain ground.
      // No network maps in tests, except a fake Google map when asked for.
      mapTilesProvider.overrideWithValue(googleMaps),
      googleMapsProvider.overrideWithValue(googleMaps),
      // Never asks the real project whether phone sign-in is on.
      phoneSignInAvailableProvider.overrideWith((ref) async => phoneSignIn),
      facebookSignInAvailableProvider.overrideWith((ref) async => facebookSignIn),
      appleSignInAvailableProvider.overrideWith((ref) async => appleSignIn),
    ];
  }
}

User fakeUser({
  String id = '22222222-2222-4222-8222-222222222222',
  Map<String, dynamic> metadata = const {'full_name': 'Lina Haddad'},
  String createdAt = '2026-09-01T00:00:00Z',
  String? lastSignInAt,
}) => User(
  id: id,
  appMetadata: const {},
  userMetadata: metadata,
  aud: 'authenticated',
  email: 'lina@example.com',
  createdAt: createdAt,
  lastSignInAt: lastSignInAt,
);

/// Pumps [child] inside the app's theme and localizations, in [lang].
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
  String lang = 'en',
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        theme: AppTheme.build(brightness: Brightness.light, lang: lang),
        home: child,
      ),
    ),
  );
}

/// Pumps [routes] under a real router, for screens that navigate on their
/// own. Starts at [initial].
Future<GoRouter> pumpRouted(
  WidgetTester tester,
  List<RouteBase> routes, {
  required List<Override> overrides,
  String initial = '/',
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: initial, routes: routes);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: MaterialApp.router(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        theme: AppTheme.build(brightness: Brightness.light, lang: 'en'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

SearchOutcome outcomeOf(List<RankedResult> results) => SearchOutcome(
  results: results,
  internalCount: results.where((r) => !r.item.isExternal).length,
  externalCount: results.where((r) => r.item.isExternal).length,
  coverage: const SearchCoverage(providersTotal: 1, unavailable: ['Licensed partner feed: not configured']),
  servedDirect: false,
);
