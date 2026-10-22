import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:akarat/core/utils/bidi.dart';
import 'package:akarat/core/widgets/coach_marks.dart';
import 'package:akarat/features/explore/explore_screen.dart';
import 'package:akarat/features/home/home_screen.dart';
import 'package:akarat/features/listings/presentation/listing_wizard_screen.dart';
import 'package:akarat/features/tour/tour.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

final _rows = [
  listing(),
  listing(
    id: '44444444-4444-4444-8444-444444444444',
    deal: 'rent',
    type: 'villa',
    hood: 'dabouq',
    price: 2400,
    titleEn: 'Garden villa with a pool',
    lat: 31.99,
    lng: 35.83,
  ),
  // No location: in the list, not on the map.
  listing(id: '77777777-7777-4777-8777-777777777777', titleEn: 'Flat with no pin', lat: null, lng: null),
];

void main() {
  group('Text direction', () {
    test('follows the first strong letter', () {
      expect(directionOf('شقة في عبدون', TextDirection.ltr), TextDirection.rtl);
      expect(directionOf('Villa in Dabouq', TextDirection.rtl), TextDirection.ltr);
      expect(directionOf('3 غرف', TextDirection.ltr), TextDirection.rtl, reason: 'digits are not strong');
      expect(directionOf('2024', TextDirection.rtl), TextDirection.rtl, reason: 'no letters: the interface decides');
    });
  });

  group('Explore map', () {
    testWidgets('opens on the map, sale and rent pinned with their prices', (tester) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: _rows)).overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text('150K'), findsOneWidget, reason: 'the sale listing');
      expect(find.text('2.4K'), findsOneWidget, reason: 'the rental');
      expect(find.text('2 on the map'), findsOneWidget, reason: 'the listing without a location is not pinned');
      expect(find.text('For sale'), findsWidgets);
      expect(find.text('For rent'), findsWidgets);

      // A pin opens a preview; the preview leads to the listing.
      await tester.tap(find.text('2.4K'));
      await tester.pumpAndSettle();
      expect(find.text('Garden villa with a pool'), findsOneWidget);
      expect(find.text('2,400 JOD/mo'), findsOneWidget);

      // Rent only.
      await tester.tap(find.text('Rent'));
      await tester.pumpAndSettle();
      expect(find.text('150K'), findsNothing);
      expect(find.text('1 on the map'), findsOneWidget);
    });

    testWidgets('cards under the map list every result, pinned ones first', (tester) async {
      // Newest first from the server, and the newest has no location.
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: [_rows[2], _rows[0], _rows[1]])).overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bright corner apartment'), findsOneWidget, reason: 'the first card has a pin');
      expect(find.text('Not on the map'), findsNothing);
      final pages = find.byType(PageView);
      for (var i = 0; i < 2; i++) {
        await tester.drag(pages, const Offset(-320, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('Flat with no pin'), findsOneWidget);
      expect(find.text('Not on the map'), findsOneWidget, reason: 'said on a line of its own');
    });

    testWidgets('the same results as a list, one tap away', (tester) async {
      await pumpScreen(
        tester,
        const ExploreScreen(),
        overrides: await TestDeps(listings: FakeListingsRepository(rows: _rows)).overrides(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('3 properties'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget, reason: 'and back to the map');
    });
  });

  group('Tours', () {
    testWidgets('a spotlight walks through the steps, back and forth, and closes', (tester) async {
      final a = GlobalKey();
      final b = GlobalKey();
      await pumpScreen(
        tester,
        Scaffold(
          body: Column(
            children: [
              SizedBox(key: a, width: 100, height: 40),
              const SizedBox(height: 300),
              SizedBox(key: b, width: 100, height: 40),
            ],
          ),
        ),
        overrides: await TestDeps().overrides(),
      );
      final context = tester.element(find.byType(Scaffold));
      final done = showCoachMarks(context, [
        CoachStep(target: a, title: (_) => 'First', body: (_) => 'The first control.'),
        CoachStep(target: b, title: (_) => 'Second', body: (_) => 'The second control.'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('First'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsNothing);
      await done;
    });

    testWidgets('the first visit to Home starts the finding tour, once', (tester) async {
      final overrides = await TestDeps(listings: FakeListingsRepository(rows: _rows))
          .overrides(prefs: {'akarat.tour.explore': false});
      await pumpScreen(tester, const HomeScreen(), overrides: overrides);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('Just describe it'), findsOneWidget);
      await tester.tap(find.text('Skip tour'));
      await tester.pumpAndSettle();
      expect(find.text('Just describe it'), findsNothing);
      final prefs = ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).read(preferencesProvider);
      expect(prefs.tourSeen('explore'), isTrue);
    });

    testWidgets('signed out, the tour ends on the Log in button and says so', (tester) async {
      final overrides = await TestDeps(listings: FakeListingsRepository(rows: _rows))
          .overrides(prefs: {'akarat.tour.explore': false});
      await pumpScreen(
        tester,
        Consumer(
          builder: (context, ref, _) {
            final t = ref.watch(tourTargetsProvider);
            return Scaffold(
              body: const HomeScreen(),
              bottomNavigationBar: AkaratNavBar(
                index: 0,
                signedIn: false,
                onSelect: (_) {},
                tabKeys: [null, t.navExplore, t.navAi, t.navSaved, t.navProfile],
              ),
            );
          },
        ),
        overrides: overrides,
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.text('Next').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('7 of 7'), findsOneWidget);
      expect(find.textContaining('Log in here to list a property'), findsOneWidget);
      expect(find.textContaining('From Profile'), findsNothing);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets('starting a first listing walks through how the form works', (tester) async {
      final overrides = await TestDeps().overrides(user: fakeUser(), prefs: {'akarat.tour.listing': false});
      await pumpScreen(tester, const ListingWizardScreen(), overrides: overrides);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      for (final title in ['Nine short steps', 'One thing at a time', 'Move on']) {
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text('Next').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Leave any time'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('What are you listing?'), findsOneWidget, reason: 'the form, ready to fill in');
    });
  });
}
