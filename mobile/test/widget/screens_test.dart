import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/ai_search/data/search_repository.dart';
import 'package:akarat/features/ai_search/domain/search_item.dart';
import 'package:akarat/features/ai_search/presentation/ai_search_screen.dart';
import 'package:akarat/features/authentication/presentation/sign_in_screen.dart';
import 'package:akarat/features/explore/filters_sheet.dart';
import 'package:akarat/features/home/home_screen.dart';
import 'package:akarat/features/listings/presentation/listing_wizard_screen.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/features/settings/settings_controller.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/models/listing_filters.dart';
import 'package:akarat/shared/widgets/property_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  group('PropertyCard', () {
    testWidgets('shows what the row has, in the reader language', (tester) async {
      var tapped = false;
      await pumpScreen(
        tester,
        Scaffold(
          body: ListView(
            children: [PropertyCard(listing: listing(), onTap: () => tapped = true)],
          ),
        ),
        overrides: await TestDeps().overrides(),
      );
      expect(find.text('150,000 JOD'), findsOneWidget);
      expect(find.text('Bright corner apartment'), findsOneWidget);
      expect(find.text('Abdoun · Amman'), findsOneWidget);
      expect(find.text('For sale'), findsOneWidget);
      await tester.tap(find.text('Bright corner apartment'));
      expect(tapped, isTrue);
    });

    testWidgets('a sold listing is marked, not hidden', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: ListView(
            children: [
              PropertyCard(
                listing: listing(status: 'sold'),
                onTap: () {},
              ),
            ],
          ),
        ),
        overrides: await TestDeps().overrides(),
      );
      expect(find.text('SOLD'), findsOneWidget);
    });

    testWidgets('the heart saves immediately and confirms', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: ListView(
            children: [PropertyCard(listing: listing(), onTap: () {})],
          ),
        ),
        overrides: await TestDeps().overrides(),
      );
      await tester.tap(find.bySemanticsLabel('Save property'));
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove from saved'), findsOneWidget);
    });
  });

  group('HomeScreen', () {
    testWidgets('lists real recent listings', (tester) async {
      final deps = TestDeps(listings: FakeListingsRepository(rows: [listing()]));
      await pumpScreen(tester, const HomeScreen(), overrides: await deps.overrides());
      await tester.pumpAndSettle();
      // As in the reference: location and search up top, no big title.
      expect(find.text('Search or describe it…'), findsOneWidget);
      expect(find.text('Recently listed'), findsOneWidget);
      expect(find.text('Bright corner apartment'), findsOneWidget);
      // No featured rows exist, so the section is not invented.
      expect(find.text('Featured'), findsNothing);
    });

    testWidgets('an empty marketplace says so honestly', (tester) async {
      await pumpScreen(tester, const HomeScreen(), overrides: await TestDeps().overrides());
      await tester.pumpAndSettle();
      expect(find.text('The marketplace is opening'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      final deps = TestDeps(listings: FakeListingsRepository(error: Exception('boom')));
      await pumpScreen(tester, const HomeScreen(), overrides: await deps.overrides());
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Arabic lays out right to left', (tester) async {
      await pumpScreen(tester, const HomeScreen(), overrides: await TestDeps().overrides(), lang: 'ar');
      await tester.pumpAndSettle();
      expect(find.text('ابحث أو صف ما تريد…'), findsOneWidget);
      final ctx = tester.element(find.byType(HomeScreen));
      expect(Directionality.of(ctx), TextDirection.rtl);
    });
  });

  group('AiSearchScreen', () {
    SearchOutcome withMatch(_) => outcomeOf([RankedResult(SearchItem.fromListing(listing()), 90)]);

    testWidgets('idle: explains itself and offers examples', (tester) async {
      await pumpScreen(
        tester,
        const AiSearchScreen(),
        overrides: await TestDeps(search: FakeSearchRepository(withMatch)).overrides(),
      );
      expect(find.text('Tell us what you are looking for.'), findsOneWidget);
      expect(find.text('Show me villas in Amman with a garden and parking'), findsOneWidget);
    });

    testWidgets('reads the request live, before anything is sent', (tester) async {
      final repo = FakeSearchRepository(withMatch);
      await pumpScreen(tester, const AiSearchScreen(), overrides: await TestDeps(search: repo).overrides());
      await tester.enterText(find.byType(TextField), '3 bedroom apartment in Abdoun under 150k');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Abdoun'), findsWidgets);
      expect(find.text('3+ bedrooms'), findsWidgets);
      expect(repo.calls, isEmpty, reason: 'parsing is local; nothing is searched until submit');
    });

    testWidgets('submitting shows ranked results, reasons and the wider market', (tester) async {
      final repo = FakeSearchRepository(withMatch);
      await pumpScreen(tester, const AiSearchScreen(), overrides: await TestDeps(search: repo).overrides());
      await tester.enterText(find.byType(TextField), 'apartment for sale in Abdoun under 150,000 JOD');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repo.calls.single.hood, 'abdoun');
      // The brief, as removable chips above the results.
      expect(find.bySemanticsLabel('Remove Abdoun'), findsOneWidget);
      expect(find.text('Bright corner apartment'), findsOneWidget);
      expect(find.text('90% match'), findsOneWidget);
      await tester.tap(find.text('Why this matches'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Within your'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Wider Jordanian market'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('OpenSooq Jordan'), findsOneWidget);
    });

    testWidgets('no matches is said plainly', (tester) async {
      final repo = FakeSearchRepository((_) => outcomeOf(const []));
      await pumpScreen(tester, const AiSearchScreen(), overrides: await TestDeps(search: repo).overrides());
      await tester.enterText(find.byType(TextField), 'castle in Wadi Rum');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Nothing in our inventory matches that yet.'), findsOneWidget);
    });
  });

  group('PropertyDetailsScreen', () {
    testWidgets('specs, amenities and an approximate location', (tester) async {
      final row = listing();
      final deps = TestDeps(listings: FakeListingsRepository(rows: [row]));
      await pumpScreen(
        tester,
        PropertyDetailsScreen(id: row.id, initial: row),
        overrides: await deps.overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text('150,000 JOD'), findsWidgets);
      expect(find.text('Property details'), findsOneWidget);
      // The facility tiles say the counts; parking is among the amenities.
      expect(find.text('3 bedrooms'), findsOneWidget);
      expect(find.text('2 bathrooms'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Elevator'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Parking'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Approximate location'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    });

    testWidgets('an inquiry needs a way to reply, then reaches the owner', (tester) async {
      final row = listing();
      final deps = TestDeps(listings: FakeListingsRepository(rows: [row]));
      await pumpScreen(
        tester,
        PropertyDetailsScreen(id: row.id, initial: row),
        overrides: await deps.overrides(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send inquiry').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Omar');
      await tester.tap(find.text('Send inquiry').last);
      await tester.pumpAndSettle();
      expect(find.text('Add an email or a phone number so the owner can reply.'), findsOneWidget);
      expect(deps.inquiries.outbox, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'omar@example.com');
      await tester.tap(find.text('Send inquiry').last);
      // The sheet closes and a confirmation shows for a moment.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(deps.inquiries.outbox.single['ownerId'], row.ownerId);
      expect(deps.inquiries.outbox.single['propertyId'], row.id);
      expect(find.text('Sent. The owner will see it in their dashboard.'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Sent. The owner will see it in their dashboard.'), findsNothing, reason: 'and then goes');
    });

    testWidgets('a sold listing takes no inquiries', (tester) async {
      final row = listing(status: 'sold');
      final deps = TestDeps(listings: FakeListingsRepository(rows: [row]));
      await pumpScreen(
        tester,
        PropertyDetailsScreen(id: row.id, initial: row),
        overrides: await deps.overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('has been sold'), findsOneWidget);
      expect(find.text('Send inquiry'), findsNothing);
    });

    testWidgets('a listing that is gone says so', (tester) async {
      await pumpScreen(
        tester,
        const PropertyDetailsScreen(id: '99999999-9999-4999-8999-999999999999'),
        overrides: await TestDeps().overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text('This listing is no longer available.'), findsOneWidget);
    });
  });

  group('SignInScreen', () {
    testWidgets('validates before sending anything', (tester) async {
      await pumpScreen(tester, const SignInScreen(), overrides: await TestDeps().overrides());
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });
  });

  group('Filters sheet', () {
    testWidgets('returns the chosen filters', (tester) async {
      ListingFilters? result;
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    result = await showFiltersSheet(context, const ListingFilters(deal: DealType.sale)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        overrides: await TestDeps().overrides(),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Villa'));
      await tester.tap(find.text('3+').first);
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(result?.type, 'villa');
      expect(result?.minBeds, 3);
      expect(result?.deal, DealType.sale);
    });
  });

  group('ListingWizardScreen', () {
    testWidgets('walks the steps and stops at a missing price', (tester) async {
      await pumpScreen(tester, const ListingWizardScreen(), overrides: await TestDeps().overrides(user: fakeUser()));
      await tester.pumpAndSettle();
      expect(find.text('What are you listing?'), findsOneWidget);
      await tester.tap(find.text('For rent'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('What kind of property?'), findsOneWidget);
      await tester.tap(find.text('Villa'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Where is it?'), findsOneWidget);
      expect(find.textContaining('Tap the map to drop the pin'), findsOneWidget, reason: 'the map needs no key now');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        find.text('Monthly rent (JOD)'),
        findsOneWidget,
        reason: 'the deal chosen in step 1 shapes the price label',
      );
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Add the price.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Monthly rent (JOD)'), '٨٠٠');
      expect(find.text('800'), findsOneWidget, reason: 'Arabic digits are folded as they are typed');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Features'), findsOneWidget);
    });
  });

  group('Language', () {
    testWidgets('switching language updates the interface without signing out', (tester) async {
      final overrides = await TestDeps().overrides(user: fakeUser());
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: Consumer(
            builder: (context, ref, _) {
              final locale = ref.watch(localeProvider);
              return MaterialApp(
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
                theme: AppTheme.build(brightness: Brightness.light, lang: locale.languageCode),
                home: const ProfileScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = Directionality.of(tester.element(find.byType(ProfileScreen)));
      await tester.tap(find.text(start == TextDirection.rtl ? 'English' : 'العربية'));
      await tester.pumpAndSettle();
      final now = Directionality.of(tester.element(find.byType(ProfileScreen)));
      expect(now, isNot(start));
      expect(find.text(now == TextDirection.rtl ? 'حسابي' : 'Profile'), findsWidgets);
      expect(find.text('lina@example.com'), findsOneWidget, reason: 'still signed in');
    });
  });
}
