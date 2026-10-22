import 'package:akarat/app/localization/l10n.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/app/theme/app_theme.dart';
import 'package:akarat/features/ai_search/presentation/ai_search_controller.dart';
import 'package:akarat/features/dashboard/dashboard_screen.dart';
import 'package:akarat/features/favorites/saved_screen.dart';
import 'package:akarat/features/listings/application/listing_wizard_controller.dart';
import 'package:akarat/features/listings/domain/listing_draft.dart';
import 'package:akarat/features/listings/presentation/listing_wizard_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/shared/models/account_models.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The interactions the design pass changed or fixed.
void main() {
  group('Saved', () {
    final search = SavedSearch(
      id: 's1',
      label: 'Villas in Dabouq',
      constraints: const SearchConstraints(deal: 'sale', type: 'villa', city: 'amman', hood: 'dabouq'),
      createdAt: DateTime(2026, 10, 2),
    );

    testWidgets('a link to the Searches tab switches to it, every time', (tester) async {
      final link = ValueNotifier<(String?, String?)>((null, null));
      final deps = TestDeps(savedSearches: FakeSavedSearchesRepository([search]));
      await pumpScreen(
        tester,
        ValueListenableBuilder(
          valueListenable: link,
          builder: (_, v, _) => SavedScreen(initialTab: v.$1, tabToken: v.$2),
        ),
        overrides: await deps.overrides(user: fakeUser()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing saved yet'), findsOneWidget);

      link.value = ('searches', '1');
      await tester.pumpAndSettle();
      expect(find.text('Villas in Dabouq'), findsOneWidget);

      // The reader goes back to Properties by hand…
      await tester.tap(find.text('Properties'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing saved yet'), findsOneWidget);

      // …and Profile's "Saved searches" (same tab, new token) still lands on Searches.
      link.value = ('searches', '2');
      await tester.pumpAndSettle();
      expect(find.text('Villas in Dabouq'), findsOneWidget);
    });

    testWidgets('removing a saved search can be undone', (tester) async {
      final repo = FakeSavedSearchesRepository([search]);
      await pumpScreen(
        tester,
        const SavedScreen(initialTab: 'searches'),
        overrides: await TestDeps(savedSearches: repo).overrides(user: fakeUser()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['s1']);
      expect(find.text('Villas in Dabouq'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Villas in Dabouq'), findsOneWidget);
    });
  });

  group('Dashboard', () {
    testWidgets('row actions live behind More, and delete asks first', (tester) async {
      final row = listing();
      final repo = FakeListingsRepository(rows: [row]);
      await pumpScreen(
        tester,
        const DashboardScreen(),
        overrides: await TestDeps(listings: repo).overrides(user: fakeUser()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hide'), findsNothing, reason: 'status actions are not laid out on the row');

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(repo.statusChanges[row.id], ListingStatus.paused);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this listing?'), findsOneWidget);
      expect(repo.deleted, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, [row.id]);
    });

    testWidgets('a new owner sees no all-zero numbers', (tester) async {
      await pumpScreen(
        tester,
        const DashboardScreen(),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: [])).overrides(user: fakeUser()),
      );
      await tester.pumpAndSettle();
      expect(find.text('No listings yet'), findsOneWidget);
      expect(find.text('Live now'), findsNothing);
    });
  });

  group('Listing flow', () {
    testWidgets('bedrooms and bathrooms are counted, not typed', (tester) async {
      await pumpScreen(tester, const ListingWizardScreen(), overrides: await TestDeps().overrides(user: fakeUser()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(ListingWizardScreen)));
      container.read(listingWizardProvider(null).notifier).goTo(3);
      await tester.pumpAndSettle();
      ListingDraft draft() => container.read(listingWizardProvider(null)).draft;

      expect(draft().bedrooms, isEmpty);
      final more = find.byTooltip('Increase');
      final less = find.byTooltip('Decrease');
      await tester.tap(more.first);
      await tester.tap(more.first);
      await tester.pump();
      expect(draft().bedrooms, '2');
      await tester.tap(less.first);
      await tester.tap(less.first);
      await tester.pump();
      expect(draft().bedrooms, '0', reason: 'a studio has no bedroom');
      await tester.tap(less.first);
      await tester.pump();
      expect(draft().bedrooms, isEmpty, reason: 'below zero is "not given", never a negative');
      expect(draft().bathrooms, isEmpty);
    });

    testWidgets('the review keeps Back in the bar and counts media in words', (tester) async {
      await pumpScreen(tester, const ListingWizardScreen(), overrides: await TestDeps().overrides(user: fakeUser()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(ListingWizardScreen)));
      container.read(listingWizardProvider(null).notifier).goTo(ListingWizardController.stepCount - 1);
      await tester.pumpAndSettle();
      expect(find.textContaining('No photos yet'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Back'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });
  });

  group('Property details', () {
    testWidgets('"Search for similar" searches the listing\'s facts, not its title', (tester) async {
      final row = listing(deal: 'rent', type: 'villa', city: 'amman', hood: 'dabouq', price: 2400, beds: 5);
      final overrides = await TestDeps(
        listings: FakeListingsRepository(rows: [row]),
        search: FakeSearchRepository((_) => outcomeOf(const [])),
      ).overrides();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PropertyDetailsScreen(id: row.id, initial: row),
          ),
          GoRoute(
            path: Routes.aiSearch,
            builder: (_, _) => const Scaffold(body: Text('AI search')),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          retry: (_, _) => null,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            theme: AppTheme.build(brightness: Brightness.light, lang: 'en'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(PropertyDetailsScreen)));
      await tester.scrollUntilVisible(find.text('Search for similar'), 400, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Search for similar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search for similar'));
      await tester.pumpAndSettle();

      expect(find.text('AI search'), findsOneWidget);
      final s = container.read(aiSearchProvider);
      expect(
        s.constraints,
        const SearchConstraints(deal: 'rent', type: 'villa', city: 'amman', hood: 'dabouq', beds: 5, budgetMax: 2800),
      );
      expect(s.turns.single, contains(row.title('en')));
    });

    testWidgets('each contact action appears once: inquiry in the bar, chat and call by the owner', (tester) async {
      final row = listing();
      await pumpScreen(
        tester,
        PropertyDetailsScreen(id: row.id, initial: row),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: [row])).overrides(),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Listed by the owner'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text('Send inquiry'), findsOneWidget, reason: 'the one action in the bar');
      expect(find.byTooltip('Call'), findsOneWidget);
      expect(find.byTooltip('WhatsApp'), findsOneWidget);
      expect(find.byTooltip('Copy number'), findsOneWidget);
      expect(find.text('150,000 JOD'), findsWidgets, reason: 'the price, in the bar');
    });
  });
}
