// Visual audit: every screen and state, rendered with the real fonts.
//
//   flutter test test/visual --update-goldens --run-skipped
//
// Writes test/visual/goldens/audit/*.png for review. Tagged `visual`, so the
// normal `flutter test` run skips it (dart_test.yaml).
@Tags(['visual'])
library;

import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:akarat/features/ai_search/data/search_repository.dart';
import 'package:akarat/features/ai_search/domain/search_item.dart';
import 'package:akarat/features/ai_search/presentation/ai_search_screen.dart';
import 'package:akarat/features/ai_search/voice/speech_service.dart';
import 'package:akarat/features/authentication/auth_service.dart';
import 'package:akarat/features/authentication/presentation/forgot_password_screen.dart';
import 'package:akarat/features/authentication/presentation/phone_auth_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_up_screen.dart';
import 'package:akarat/features/dashboard/dashboard_screen.dart';
import 'package:akarat/features/explore/explore_screen.dart';
import 'package:akarat/features/favorites/saved_screen.dart';
import 'package:akarat/features/home/home_screen.dart';
import 'package:akarat/features/inquiries/inquiries_screen.dart';
import 'package:akarat/features/listings/presentation/listing_wizard_screen.dart';
import 'package:akarat/features/onboarding/onboarding_screen.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/features/settings/legal_screen.dart';
import 'package:akarat/shared/models/account_models.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OtpChannel, User, UserIdentity;

import '../support/fakes.dart';
import '../support/harness.dart';
import 'render.dart';

final rows = [
  listing(),
  listing(
    id: '44444444-4444-4444-8444-444444444444',
    deal: 'rent',
    type: 'villa',
    hood: 'dabouq',
    price: 2400,
    beds: 5,
    baths: 4,
    area: 520,
    titleEn: 'Garden villa with a pool',
    titleAr: 'فيلا بحديقة ومسبح',
    amenities: const ['garden', 'pool', 'parking', 'security', 'heating', 'ac'],
    verified: true,
  ),
  listing(
    id: '55555555-5555-4555-8555-555555555555',
    status: 'sold',
    type: 'land',
    city: 'salt',
    hood: null,
    price: 30000,
    beds: null,
    baths: null,
    area: 900,
    titleEn: 'Residential plot near Salt',
    titleAr: 'قطعة أرض سكنية قرب السلط',
    amenities: const [],
  ),
  listing(
    id: '66666666-6666-4666-8666-666666666666',
    status: 'paused',
    hood: 'khalda',
    price: 98000,
    beds: 2,
    titleEn: 'Two-bedroom flat in Khalda',
    titleAr: 'شقة غرفتين في خلدا',
  ),
];

SearchOutcome results() => outcomeOf([
  RankedResult(SearchItem.fromListing(rows[0]), 92),
  RankedResult(SearchItem.fromListing(rows[3]), 71),
  const RankedResult(
    SearchItem(
      id: 'x-1',
      titleEn: 'Apartment for sale in Abdoun',
      titleAr: 'Apartment for sale in Abdoun',
      source: 'opensooq',
      kind: 'known_marketplace',
      deal: 'sale',
      city: 'amman',
      hood: 'abdoun',
      price: 155000,
      beds: 3,
      checked: 2,
      url: 'https://jo.opensooq.com/en/x',
    ),
    64,
  ),
]);

Future<void> submit(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextField), q);
  await t.testTextInput.receiveAction(TextInputAction.search);
}

void main() {
  setUpAll(loadRealFonts);

  group('onboarding', () {
    testWidgets('compact en', (t) async {
      await render(
        t,
        'onboarding_compact_en',
        const OnboardingScreen(),
        overrides: await TestDeps().overrides(),
        device: Device.compact,
      );
    });
    testWidgets('phone ar', (t) async {
      await render(t, 'onboarding_ar', const OnboardingScreen(), overrides: await TestDeps().overrides(), lang: 'ar');
    });
  });

  group('home', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('data $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(t, 'home_$lang', withNav(const HomeScreen(), NavTab.home), overrides: await deps.overrides(), lang: lang);
      });
    }
    testWidgets('scrolled', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'home_scrolled',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        interact: (t) => t.drag(find.byType(CustomScrollView), const Offset(0, -700)),
      );
    });
    testWidgets('dark', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'home_dark',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        brightness: Brightness.dark,
      );
    });
    testWidgets('compact', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'home_compact',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        device: Device.compact,
      );
    });
    testWidgets('tablet', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'home_tablet',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        device: Device.tablet,
      );
    });
    testWidgets('loading', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(pending: true));
      await render(t, 'home_loading', withNav(const HomeScreen(), NavTab.home), overrides: await deps.overrides());
    });
    testWidgets('empty', (t) async {
      await render(t, 'home_empty', withNav(const HomeScreen(), NavTab.home), overrides: await TestDeps().overrides());
    });
    testWidgets('error', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(error: const SocketExceptionLike()));
      await render(t, 'home_error', withNav(const HomeScreen(), NavTab.home), overrides: await deps.overrides());
    });
    testWidgets('large text ar', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'home_text16_ar',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        lang: 'ar',
        textScale: 1.6,
      );
    });
  });

  group('explore', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('data $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'explore_$lang',
          withNav(const ExploreScreen(), NavTab.explore),
          overrides: await deps.overrides(),
          lang: lang,
        );
      });
    }
    testWidgets('tablet', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'explore_tablet',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        device: Device.tablet,
      );
    });
    testWidgets('loading', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(pending: true));
      await render(t, 'explore_loading', withNav(const ExploreScreen(), NavTab.explore), overrides: await deps.overrides());
    });
    testWidgets('empty', (t) async {
      await render(t, 'explore_empty', withNav(const ExploreScreen(), NavTab.explore), overrides: await TestDeps().overrides());
    });
    testWidgets('list view', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'explore_list',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        interact: (t) => t.tap(find.text('List')),
      );
    });
    testWidgets('map tour', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'explore_tour',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(prefs: {'akarat.tour.map': false}),
        interact: (t) => t.pump(const Duration(milliseconds: 900)),
      );
    });
    testWidgets('filters sheet', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'explore_filters',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        interact: (t) => t.tap(find.byTooltip('Filters')),
      );
    });
    testWidgets('filters sheet ar', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'explore_filters_ar',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        lang: 'ar',
        interact: (t) => t.tap(find.byTooltip('الفلاتر')),
      );
    });
  });

  group('ai search', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('idle $lang', (t) async {
        final deps = TestDeps(search: FakeSearchRepository((_) => results()));
        await render(
          t,
          'ai_idle_$lang',
          withNav(const AiSearchScreen(), NavTab.ai),
          overrides: await deps.overrides(),
          lang: lang,
        );
      });
      testWidgets('results $lang', (t) async {
        final deps = TestDeps(search: FakeSearchRepository((_) => results()));
        await render(
          t,
          'ai_results_$lang',
          withNav(const AiSearchScreen(), NavTab.ai),
          overrides: await deps.overrides(),
          lang: lang,
          interact: (t) => submit(
            t,
            lang == 'ar' ? 'بدي شقة بعبدون ٣ غرف بأقل من ١٥٠ ألف' : '3 bedroom apartment in Abdoun under 150k',
          ),
        );
      });
    }
    testWidgets('voice listening ar', (t) async {
      final speech = FakeSpeechService();
      await render(
        t,
        'ai_voice_listening_ar',
        withNav(const AiSearchScreen(voiceToken: '1'), NavTab.ai),
        overrides: await TestDeps(speech: speech).overrides(),
        lang: 'ar',
        interact: (t) async {
          for (final db in const <double>[-2, 3, 9, 5, 10, 2, 8, 6]) {
            speech.level(db);
          }
          speech.say('بدي شقة بعبدون ثلاث غرف');
        },
      );
    });
    testWidgets('voice review', (t) async {
      final speech = FakeSpeechService();
      await render(
        t,
        'ai_voice_review',
        withNav(const AiSearchScreen(voiceToken: '1'), NavTab.ai),
        overrides: await TestDeps(speech: speech).overrides(),
        interact: (t) async => speech.say(
          'three bedroom apartment in Abdoun under one hundred fifty thousand JOD with parking',
          done: true,
        ),
      );
    });
    testWidgets('voice denied', (t) async {
      await render(
        t,
        'ai_voice_denied',
        withNav(const AiSearchScreen(voiceToken: '1'), NavTab.ai),
        overrides: await TestDeps(speech: FakeSpeechService(ready: false, failure: SpeechFailure.denied)).overrides(),
      );
    });
    testWidgets('typing preview', (t) async {
      final deps = TestDeps(search: FakeSearchRepository((_) => results()));
      await render(
        t,
        'ai_typing',
        withNav(const AiSearchScreen(), NavTab.ai),
        overrides: await deps.overrides(),
        interact: (t) async {
          await t.enterText(find.byType(TextField), 'villa for rent in Dabouq with a pool under 3000 a month');
          await t.pump(const Duration(milliseconds: 400));
        },
      );
    });
    testWidgets('results scrolled', (t) async {
      final deps = TestDeps(search: FakeSearchRepository((_) => results()));
      await render(
        t,
        'ai_results_scrolled',
        withNav(const AiSearchScreen(), NavTab.ai),
        overrides: await deps.overrides(),
        interact: (t) async {
          await submit(t, '3 bedroom apartment for sale in Abdoun under 150k');
          await t.pump(const Duration(milliseconds: 600));
          await t.tap(find.text('Why this matches').first);
          await t.pump(const Duration(milliseconds: 600));
          await t.drag(find.byType(Scrollable).first, const Offset(0, -600));
        },
      );
    });
    testWidgets('no results + wider market', (t) async {
      final deps = TestDeps(search: FakeSearchRepository((_) => outcomeOf(const [])));
      await render(
        t,
        'ai_none',
        withNav(const AiSearchScreen(), NavTab.ai),
        overrides: await deps.overrides(),
        interact: (t) async {
          await submit(t, 'castle in Wadi Rum');
          await t.pump(const Duration(milliseconds: 600));
          await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
        },
      );
    });
  });

  group('details', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('top $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'details_top_$lang',
          PropertyDetailsScreen(id: rows[1].id, initial: rows[1]),
          overrides: await deps.overrides(),
          lang: lang,
        );
      });
      testWidgets('lower $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'details_lower_$lang',
          PropertyDetailsScreen(id: rows[1].id, initial: rows[1]),
          overrides: await deps.overrides(),
          lang: lang,
          interact: (t) => t.drag(find.byType(CustomScrollView), const Offset(0, -1100)),
        );
      });
    }
    testWidgets('bottom', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'details_bottom',
        PropertyDetailsScreen(id: rows[0].id, initial: rows[0]),
        overrides: await deps.overrides(),
        interact: (t) => t.drag(find.byType(CustomScrollView), const Offset(0, -2400)),
      );
    });
    testWidgets('sold', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'details_sold',
        PropertyDetailsScreen(id: rows[2].id, initial: rows[2]),
        overrides: await deps.overrides(),
      );
    });
    testWidgets('tablet', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'details_tablet',
        PropertyDetailsScreen(id: rows[1].id, initial: rows[1]),
        overrides: await deps.overrides(),
        device: Device.tablet,
      );
    });
    testWidgets('dark', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'details_dark',
        PropertyDetailsScreen(id: rows[1].id, initial: rows[1]),
        overrides: await deps.overrides(),
        brightness: Brightness.dark,
      );
    });
    testWidgets('inquiry sheet', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'details_inquiry',
        PropertyDetailsScreen(id: rows[0].id, initial: rows[0]),
        overrides: await deps.overrides(),
        interact: (t) => t.tap(find.text('Send inquiry').last),
      );
    });
    testWidgets('loading', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(pending: true));
      await render(t, 'details_loading', PropertyDetailsScreen(id: rows[0].id), overrides: await deps.overrides());
    });
  });

  group('saved', () {
    testWidgets('empty guest', (t) async {
      await render(t, 'saved_empty', withNav(const SavedScreen(), NavTab.saved), overrides: await TestDeps().overrides());
    });
    testWidgets('with items', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'saved_items',
        withNav(const SavedScreen(), NavTab.saved),
        overrides: await deps.overrides(
          prefs: {
            'akarat.onboarded': true,
            'akarat.favorites.local': [rows[0].id, rows[1].id],
          },
        ),
      );
    });
    testWidgets('searches signed in', (t) async {
      final deps = TestDeps(
        savedSearches: FakeSavedSearchesRepository([
          SavedSearch(
            id: 's1',
            label: '3 bedroom apartment in Abdoun under 150k',
            constraints: const SearchConstraints(
              deal: 'sale',
              city: 'amman',
              hood: 'abdoun',
              beds: 3,
              budgetMax: 150000,
              type: 'apartment',
            ),
            createdAt: DateTime(2026, 10, 2),
          ),
        ]),
      );
      await render(
        t,
        'saved_searches',
        withNav(const SavedScreen(initialTab: 'searches'), NavTab.saved),
        overrides: await deps.overrides(user: fakeUser()),
      );
    });
    testWidgets('items tablet', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'saved_tablet',
        withNav(const SavedScreen(), NavTab.saved),
        overrides: await deps.overrides(
          prefs: {
            'akarat.onboarded': true,
            'akarat.favorites.local': [rows[0].id, rows[1].id, rows[3].id],
          },
        ),
        device: Device.tablet,
      );
    });
    testWidgets('searches ar', (t) async {
      final deps = TestDeps(
        savedSearches: FakeSavedSearchesRepository([
          SavedSearch(
            id: 's1',
            label: 'شقة 3 غرف في عبدون',
            constraints: const SearchConstraints(
              deal: 'sale',
              city: 'amman',
              hood: 'abdoun',
              beds: 3,
              type: 'apartment',
            ),
            createdAt: DateTime(2026, 10, 2),
          ),
        ]),
      );
      await render(
        t,
        'saved_searches_ar',
        withNav(const SavedScreen(initialTab: 'searches'), NavTab.saved),
        overrides: await deps.overrides(user: fakeUser()),
        lang: 'ar',
      );
    });
  });

  group('profile', () {
    testWidgets('guest en', (t) async {
      await render(t, 'profile_guest', withNav(const ProfileScreen(), NavTab.profile), overrides: await TestDeps().overrides());
    });
    testWidgets('signed in ar', (t) async {
      final deps = TestDeps(
        profile: FakeProfileRepository(
          const Profile(id: 'u', fullName: 'Lina Haddad', phone: '+962 79 123 4567', verified: true),
        ),
      );
      await render(
        t,
        'profile_signed_ar',
        withNav(const ProfileScreen(), NavTab.profile),
        overrides: await deps.overrides(user: fakeUser()),
        lang: 'ar',
      );
    });
    testWidgets('signed in dark', (t) async {
      final deps = TestDeps(
        profile: FakeProfileRepository(const Profile(id: 'u', fullName: 'Lina Haddad')),
      );
      await render(
        t,
        'profile_dark',
        withNav(const ProfileScreen(), NavTab.profile),
        overrides: await deps.overrides(user: fakeUser()),
        brightness: Brightness.dark,
      );
    });
    testWidgets('signed in tablet', (t) async {
      final deps = TestDeps(
        profile: FakeProfileRepository(const Profile(id: 'u', fullName: 'Lina Haddad', verified: true)),
      );
      await render(
        t,
        'profile_tablet',
        withNav(const ProfileScreen(), NavTab.profile),
        overrides: await deps.overrides(user: fakeUser()),
        device: Device.tablet,
      );
    });
    testWidgets('legal', (t) async {
      await render(t, 'legal_privacy', const LegalScreen(doc: 'privacy'), overrides: await TestDeps().overrides());
    });
  });

  group('owner', () {
    testWidgets('dashboard', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(t, 'dashboard', const DashboardScreen(), overrides: await deps.overrides(user: fakeUser()));
    });
    testWidgets('dashboard ar', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dashboard_ar',
        const DashboardScreen(),
        overrides: await deps.overrides(user: fakeUser()),
        lang: 'ar',
      );
    });
    testWidgets('dashboard more', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dashboard_more',
        const DashboardScreen(),
        overrides: await deps.overrides(user: fakeUser()),
        interact: (t) => t.tap(find.byTooltip('More').first),
      );
    });
    testWidgets('dashboard empty', (t) async {
      await render(
        t,
        'dashboard_empty',
        const DashboardScreen(),
        overrides: await TestDeps().overrides(user: fakeUser()),
      );
    });
    testWidgets('inquiries', (t) async {
      final deps = TestDeps(
        inquiries: FakeInquiriesRepository(
          inbox: [
            Inquiry(
              id: 'i1',
              propertyId: rows[0].id,
              ownerId: rows[0].ownerId,
              name: 'Omar Khalil',
              email: 'omar@example.com',
              phone: '0791234567',
              message: 'Hello, is the apartment still available? Could I view it on Saturday morning?',
              status: 'new',
              createdAt: DateTime(2026, 10, 12),
              propertyTitleEn: 'Bright corner apartment',
            ),
          ],
        ),
      );
      await render(t, 'inquiries', const InquiriesScreen(), overrides: await deps.overrides(user: fakeUser()));
    });
  });

  group('wizard', () {
    for (var step = 0; step < 9; step++) {
      testWidgets('step ${step + 1}', (t) async {
        await render(
          t,
          'wizard_${step + 1}',
          const ListingWizardScreen(),
          overrides: await TestDeps().overrides(user: fakeUser()),
          interact: (t) async {
            for (var i = 0; i < step; i++) {
              if (i == 4) await t.enterText(find.byType(TextField).first, '150000');
              if (i == 6) await t.enterText(find.byType(TextField).at(1), 'Bright corner apartment');
              await t.tap(find.text('Next'));
              for (var k = 0; k < 3; k++) {
                await t.pump(const Duration(milliseconds: 200));
              }
            }
          },
        );
      });
    }
    testWidgets('details counted', (t) async {
      await render(
        t,
        'wizard_4_counted',
        const ListingWizardScreen(),
        overrides: await TestDeps().overrides(user: fakeUser()),
        interact: (t) async {
          for (var i = 0; i < 3; i++) {
            await t.tap(find.text('Next'));
            for (var k = 0; k < 3; k++) {
              await t.pump(const Duration(milliseconds: 200));
            }
          }
          for (var i = 0; i < 3; i++) {
            await t.tap(find.byTooltip('Increase').first);
            await t.pump();
          }
          await t.tap(find.byTooltip('Increase').last);
          await t.pump();
        },
      );
    });
    testWidgets('location ar', (t) async {
      await render(
        t,
        'wizard_3_ar',
        const ListingWizardScreen(),
        overrides: await TestDeps().overrides(user: fakeUser()),
        lang: 'ar',
        interact: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.tap(find.text('التالي'));
            for (var k = 0; k < 3; k++) {
              await t.pump(const Duration(milliseconds: 200));
            }
          }
        },
      );
    });
  });

  group('auth', () {
    testWidgets('sign in', (t) async {
      await render(t, 'auth_signin', const SignInScreen(), overrides: await TestDeps().overrides());
    });
    testWidgets('sign up ar', (t) async {
      await render(t, 'auth_signup_ar', const SignUpScreen(), overrides: await TestDeps().overrides(), lang: 'ar');
    });
    testWidgets('forgot', (t) async {
      await render(t, 'auth_forgot', const ForgotPasswordScreen(), overrides: await TestDeps().overrides());
    });
    testWidgets('sign in errors', (t) async {
      await render(
        t,
        'auth_signin_errors',
        const SignInScreen(),
        overrides: await TestDeps().overrides(),
        interact: (t) => t.tap(find.widgetWithText(FilledButton, 'Sign in')),
      );
    });
  });

  // Text at the largest size the app allows (1.6×), and the smallest
  // phone with large text: nothing may clip or overflow.
  group('typography', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('details large text $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'type_details_xl_$lang',
          PropertyDetailsScreen(id: rows[1].id, initial: rows[1]),
          overrides: await deps.overrides(),
          lang: lang,
          textScale: 1.6,
        );
      });
      testWidgets('explore list large text $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'type_explore_xl_$lang',
          withNav(const ExploreScreen(), NavTab.explore),
          overrides: await deps.overrides(),
          lang: lang,
          textScale: 1.6,
          interact: (t) async {
            await t.tap(find.byIcon(Icons.view_agenda_outlined));
            await t.pumpAndSettle();
          },
        );
      });
      testWidgets('small phone $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'type_home_compact_$lang',
          withNav(const HomeScreen(), NavTab.home),
          overrides: await deps.overrides(),
          lang: lang,
          device: Device.compact,
          textScale: 1.3,
        );
      });
    }
    testWidgets('home large text en', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'type_home_xl_en',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        textScale: 1.6,
      );
    });
    testWidgets('sign in large text', (t) async {
      await render(t, 'type_signin_xl', const SignInScreen(), overrides: await TestDeps().overrides(), textScale: 1.6);
    });
  });

  group('landscape', () {
    testWidgets('home', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'landscape_home',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(),
        device: Device.landscape,
      );
    });
  });

  group('tour', () {
    // Lina's account, just made: her welcome is owed.
    final lina = fakeUser(metadata: const {'full_name': 'Lina Haddad', 'tour_pending': true, 'tours_done': []});
    Future<void> next(WidgetTester t, int times, {String label = 'Next'}) async {
      for (var i = 0; i < times; i++) {
        await t.tap(find.text(label).last);
        await t.pump(const Duration(milliseconds: 400));
      }
    }

    for (final lang in ['en', 'ar']) {
      testWidgets('welcome $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'tour_welcome_$lang',
          withNav(const HomeScreen(), NavTab.home),
          overrides: await deps.overrides(user: lina, prefs: {'akarat.tour.explore': false}),
          lang: lang,
        );
      });
      testWidgets('search large text $lang', (t) async {
        final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
        await render(
          t,
          'tour_search_xl_$lang',
          withNav(const HomeScreen(), NavTab.home),
          overrides: await deps.overrides(user: lina, prefs: {'akarat.tour.explore': false}),
          lang: lang,
          textScale: 1.6,
          interact: (t) => next(t, 1, label: lang == 'ar' ? 'التالي' : 'Next'),
        );
      });
    }
    testWidgets('dark', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'tour_dark',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(prefs: {'akarat.tour.explore': false}),
        brightness: Brightness.dark,
        interact: (t) => next(t, 1),
      );
    });
    testWidgets('welcome after the guest tour ar', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'tour_welcome_brief_ar',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(user: lina),
        lang: 'ar',
      );
    });
    testWidgets('landscape', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'tour_landscape',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(prefs: {'akarat.tour.explore': false}),
        device: Device.landscape,
        textScale: 1.3,
        interact: (t) => next(t, 1),
      );
    });
    testWidgets('tablet tab bar', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'tour_tablet',
        withNav(const HomeScreen(), NavTab.home),
        overrides: await deps.overrides(prefs: {'akarat.tour.explore': false}),
        device: Device.tablet,
        interact: (t) => next(t, 5),
      );
    });
    testWidgets('a listing', (t) async {
      // No photos here (the image cache needs plugins the test runner lacks),
      // so the tour is saving and contacting the owner.
      final row = listing(owner: '99999999-9999-4999-8999-999999999999');
      await render(
        t,
        'tour_property',
        PropertyDetailsScreen(id: row.id, initial: row),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: [row]))
            .overrides(prefs: {'akarat.tour.property': false}),
        interact: (t) => next(t, 1),
      );
    });
  });

  group('matte dark', () {
    const dark = Brightness.dark;
    testWidgets('explore map', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dark_explore',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        brightness: dark,
      );
    });
    testWidgets('explore list', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dark_explore_list',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        brightness: dark,
        interact: (t) => t.tap(find.text('List')),
      );
    });
    testWidgets('filters', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dark_filters',
        withNav(const ExploreScreen(), NavTab.explore),
        overrides: await deps.overrides(),
        brightness: dark,
        interact: (t) => t.tap(find.byTooltip('Filters')),
      );
    });
    testWidgets('ai results', (t) async {
      final deps = TestDeps(search: FakeSearchRepository((_) => results()));
      await render(
        t,
        'dark_ai_results',
        withNav(const AiSearchScreen(), NavTab.ai),
        overrides: await deps.overrides(),
        brightness: dark,
        interact: (t) async {
          await submit(t, '3 bedroom apartment for sale in Abdoun under 150k');
          await t.pump(const Duration(milliseconds: 600));
        },
      );
    });
    testWidgets('saved', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dark_saved',
        withNav(const SavedScreen(), NavTab.saved),
        overrides: await deps.overrides(
          prefs: {
            'akarat.onboarded': true,
            'akarat.favorites.local': [rows[0].id, rows[1].id],
          },
        ),
        brightness: dark,
      );
    });
    testWidgets('dashboard', (t) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: rows));
      await render(
        t,
        'dark_dashboard',
        const DashboardScreen(),
        overrides: await deps.overrides(user: fakeUser()),
        brightness: dark,
      );
    });
    testWidgets('sign in', (t) async {
      await render(t, 'dark_signin', const SignInScreen(), overrides: await TestDeps().overrides(), brightness: dark);
    });
    testWidgets('listing form', (t) async {
      await render(
        t,
        'dark_wizard',
        const ListingWizardScreen(),
        overrides: await TestDeps().overrides(user: fakeUser()),
        brightness: dark,
      );
    });
  });

  group('phone sign-in', () {
    Future<List<Override>> deps({User? user}) async => [
      ...await TestDeps().overrides(user: user, phoneSignIn: true),
      authServiceProvider.overrideWithValue(_RenderPhoneAuth()),
    ];
    Future<void> sendCode(WidgetTester t) async {
      await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0791234567');
      await t.tap(find.text('Send code'));
    }

    testWidgets('sign-in offers it', (t) async {
      await render(t, 'phone_signin_button', const SignInScreen(), overrides: await deps());
    });
    testWidgets('number', (t) async {
      await render(t, 'phone_number', const PhoneAuthScreen(kind: PhoneAuthKind.signIn), overrides: await deps());
    });
    testWidgets('number, refused', (t) async {
      await render(
        t,
        'phone_number_refused',
        const PhoneAuthScreen(kind: PhoneAuthKind.signIn),
        overrides: await deps(),
        interact: (t) async {
          await t.enterText(find.widgetWithText(TextFormField, 'Phone number'), '7912');
          await t.tap(find.text('Send code'));
        },
      );
    });
    testWidgets('countries', (t) async {
      await render(
        t,
        'phone_countries',
        const PhoneAuthScreen(kind: PhoneAuthKind.signIn),
        overrides: await deps(),
        interact: (t) => t.tap(find.text('+962')),
      );
    });
    testWidgets('sign-up, Arabic', (t) async {
      await render(
        t,
        'phone_signup_ar',
        const PhoneAuthScreen(kind: PhoneAuthKind.signUp),
        overrides: await deps(),
        lang: 'ar',
      );
    });
    testWidgets('code', (t) async {
      await render(
        t,
        'phone_code',
        const PhoneAuthScreen(kind: PhoneAuthKind.signIn),
        overrides: await deps(),
        interact: sendCode,
      );
    });
    testWidgets('code, dark, Arabic', (t) async {
      await render(
        t,
        'phone_code_dark_ar',
        const PhoneAuthScreen(kind: PhoneAuthKind.signIn),
        overrides: await deps(),
        lang: 'ar',
        brightness: Brightness.dark,
        interact: (t) async {
          await t.enterText(find.byType(TextFormField), '0791234567');
          await t.tap(find.text('إرسال الرمز'));
        },
      );
    });
    testWidgets('link, dark', (t) async {
      await render(
        t,
        'phone_link_dark',
        const PhoneAuthScreen(kind: PhoneAuthKind.link),
        overrides: await deps(user: fakeUser()),
        brightness: Brightness.dark,
      );
    });
    testWidgets('profile row', (t) async {
      await render(
        t,
        'phone_profile',
        withNav(const ProfileScreen(), NavTab.profile),
        overrides: await deps(user: fakeUser()),
        interact: (t) => t.drag(find.byType(Scrollable).first, const Offset(0, -900)),
      );
    });
  });

  group('facebook', () {
    User withFacebook() => User(
      id: '22222222-2222-4222-8222-222222222222',
      appMetadata: const {},
      userMetadata: const {'full_name': 'Lina Haddad'},
      aud: 'authenticated',
      email: 'lina@example.com',
      createdAt: '2026-09-01T00:00:00Z',
      identities: [
        for (final p in ['email', 'facebook'])
          UserIdentity(
            id: p,
            userId: '22222222-2222-4222-8222-222222222222',
            identityData: const {},
            identityId: p,
            provider: p,
            createdAt: '2026-09-01T00:00:00Z',
            lastSignInAt: '2026-09-01T00:00:00Z',
          ),
      ],
    );
    testWidgets('sign-in, every way in', (t) async {
      await render(
        t,
        'facebook_signin',
        const SignInScreen(),
        overrides: await TestDeps().overrides(facebookSignIn: true, phoneSignIn: true),
      );
    });
    testWidgets('sign-up, Arabic', (t) async {
      await render(
        t,
        'facebook_signup_ar',
        const SignUpScreen(),
        overrides: await TestDeps().overrides(facebookSignIn: true, phoneSignIn: true),
        lang: 'ar',
        interact: (t) => t.drag(find.byType(Scrollable).first, const Offset(0, -500)),
      );
    });
    testWidgets('profile, connected, dark', (t) async {
      await render(
        t,
        'facebook_profile_dark',
        withNav(const ProfileScreen(), NavTab.profile),
        overrides: await TestDeps().overrides(user: withFacebook(), facebookSignIn: true, phoneSignIn: true),
        brightness: Brightness.dark,
        interact: (t) => t.drag(find.byType(Scrollable).first, const Offset(0, -900)),
      );
    });
  });
}

/// An offline failure without importing dart:io into the fakes' callers.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
  @override
  String toString() => 'SocketException: Failed host lookup';
}

/// Phone codes for the renders: every request succeeds, nothing is sent.
class _RenderPhoneAuth extends Fake implements AuthService {
  @override
  OtpChannel get channel => OtpChannel.sms;

  @override
  Future<void> sendPhoneCode(String phone, {bool create = false, Map<String, Object> data = const {}}) async {}

  @override
  Future<void> startPhoneLink(String phone) async {}
}
