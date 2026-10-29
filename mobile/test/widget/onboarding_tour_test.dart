import 'dart:io';

import 'package:akarat/app/router/routes.dart';
import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:akarat/core/widgets/coach_marks.dart';
import 'package:akarat/features/home/home_screen.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/features/tour/tour.dart';
import 'package:akarat/features/tour/tour_store.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:akarat/shared/services/supabase_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Lina's account, moments after the sign-up form made it.
final _newAccount = fakeUser(metadata: const {'full_name': 'Lina Haddad', 'tour_pending': true, 'tours_done': []});

/// An account from before tours were kept on accounts: no tour keys at all.
final _oldAccount = fakeUser(
  metadata: const {'full_name': 'Omar Saleh'},
  createdAt: '2025-03-02T10:00:00Z',
  lastSignInAt: '2026-10-16T08:00:00Z',
);

/// A TourStore over mock preferences, recording what it writes to the account.
Future<({TourStore store, Preferences prefs, List<Map<String, Object>> saves})> _store({
  User? Function()? user,
  Map<String, Object> prefs = const {},
  bool offline = false,
}) async {
  SharedPreferences.setMockInitialValues({'akarat.onboarded': true, ...prefs});
  final p = Preferences(await SharedPreferences.getInstance());
  final saves = <Map<String, Object>>[];
  final store = TourStore(
    p,
    user: user ?? () => null,
    save: (data) async {
      if (offline) throw const SocketException('offline');
      saves.add(data);
      return null;
    },
  );
  return (store: store, prefs: p, saves: saves);
}

/// The app's fakes, with the account writes recorded instead of sent.
Future<(List<Override>, List<Map<String, Object>>)> _deps({
  User? user,
  Map<String, Object> prefs = const {},
  List<Listing>? rows,
}) async {
  final saves = <Map<String, Object>>[];
  final base = await TestDeps(listings: FakeListingsRepository(rows: rows ?? [listing()]))
      .overrides(user: user, prefs: prefs);
  return (
    [
      ...base,
      tourStoreProvider.overrideWith(
        (ref) => TourStore(
          ref.watch(preferencesProvider),
          user: () => ref.read(currentUserProvider),
          save: (data) async {
            saves.add(data);
            return null;
          },
        ),
      ),
    ],
    saves,
  );
}

/// Home with the tab bar under it, as in the app.
Widget _homeWithTabs({required bool signedIn}) => Consumer(
  builder: (context, ref, _) {
    final t = ref.watch(tourTargetsProvider);
    return Scaffold(
      body: const HomeScreen(),
      bottomNavigationBar: AkaratNavBar(
        index: 0,
        signedIn: signedIn,
        onSelect: (_) {},
        tabKeys: [null, t.navExplore, t.navAi, t.navSaved, t.navProfile],
      ),
    );
  },
);

/// Past the tour's settle delay, and its fade in.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
}

/// The tour card on screen.
Finder _card() =>
    find.ancestor(of: find.textContaining(RegExp(r'^\d+ (of|من) \d+$')), matching: find.byType(Material)).first;

/// "3 of 8" → (3, 8).
(int, int) _position(WidgetTester tester) {
  final text = tester.widget<Text>(find.textContaining(RegExp(r'^\d+ (of|من) \d+$'))).data!;
  final n = RegExp(r'\d+').allMatches(text).map((m) => int.parse(m.group(0)!)).toList();
  return (n[0], n[1]);
}

Future<void> _next(WidgetTester tester, {String label = 'Next'}) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The system back gesture.
Future<void> _systemBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
}

void main() {
  group('Tour progress', () {
    test('a new account from the sign-up form is owed its welcome, once', () async {
      var user = _newAccount;
      final s = await _store(user: () => user, prefs: {'akarat.tour.explore': false});
      expect(TourStore.isNewAccount(user), isTrue);
      expect(s.store.welcomeOwed, isTrue);
      expect(s.store.shouldStart(TourId.explore), isTrue);

      await s.store.markDone(TourId.explore);
      expect(s.saves.single, {
        'tours_done': ['explore'],
        'tour_pending': false,
      });
      expect(s.store.welcomeOwed, isFalse, reason: 'welcomed on this phone, before the account says so');
      // The account catches up.
      user = fakeUser(metadata: {'full_name': 'Lina Haddad', ...s.saves.single});
      expect(s.store.shouldStart(TourId.explore), isFalse);
      expect(TourStore.isNewAccount(user), isFalse);
    });

    test('an account from before is never treated as new, even on a phone that never showed the tour', () async {
      final s = await _store(user: () => _oldAccount, prefs: {'akarat.tour.explore': false});
      expect(TourStore.isNewAccount(_oldAccount), isFalse);
      expect(s.store.welcomeOwed, isFalse);
      expect(s.store.shouldStart(TourId.explore), isFalse);
      // Its first launch on this version records that, once.
      await s.store.sync();
      expect(s.saves.single, {'tour_pending': false, 'tours_done': <String>[]});
    });

    test("a Google account's very first sign-in is new; a later one is not", () async {
      final first = fakeUser(
        metadata: const {'full_name': 'Sara Nabulsi'},
        createdAt: '2026-10-16T09:00:00Z',
        lastSignInAt: '2026-10-16T09:00:02Z',
      );
      final s = await _store(user: () => first);
      expect(TourStore.isNewAccount(first), isTrue);
      expect(s.store.welcomeOwed, isTrue, reason: 'owed at once, before the account is written');
      await s.store.sync();
      expect(s.saves.single['tour_pending'], isTrue);

      final later = fakeUser(
        metadata: const {'full_name': 'Sara Nabulsi'},
        createdAt: '2026-10-16T09:00:00Z',
        lastSignInAt: '2026-10-20T18:30:00Z',
      );
      expect(TourStore.isNewAccount(later), isFalse);
    });

    test('signing in, the account is brought up to date even before the app knows who signed in', () async {
      // The auth event arrives before the app's user state is updated.
      final s = await _store(user: () => null, prefs: {'akarat.tour.explore': true});
      await s.store.sync(_oldAccount);
      expect(s.saves.single, {
        'tour_pending': false,
        'tours_done': ['explore'],
      });
    });

    test('tours taken on another phone are not repeated on this one', () async {
      final user = fakeUser(
        metadata: const {
          'tour_pending': false,
          'tours_done': ['explore', 'map'],
        },
      );
      final s = await _store(user: () => user, prefs: {'akarat.tour.explore': false, 'akarat.tour.map': false});
      expect(s.store.shouldStart(TourId.map), isFalse);
      expect(s.store.shouldStart(TourId.listing), isTrue, reason: 'not taken anywhere yet');
      await s.store.sync();
      expect(s.prefs.tourSeen('map'), isTrue, reason: 'kept on the phone too, so it holds after signing out');
      expect(s.saves, isEmpty, reason: 'nothing new to tell the account');
    });

    test('signed out and back in, the tour is not shown again', () async {
      User? user = _newAccount;
      final s = await _store(user: () => user, prefs: {'akarat.tour.explore': false});
      await s.store.markDone(TourId.explore);
      user = null;
      expect(s.store.shouldStart(TourId.explore), isFalse, reason: 'signed out: this phone has shown it');
      user = fakeUser(
        metadata: const {
          'tour_pending': false,
          'tours_done': ['explore'],
        },
      );
      expect(s.store.shouldStart(TourId.explore), isFalse, reason: 'signed back in');
    });

    test('a second person signing up on the same phone is welcomed too', () async {
      User user = _newAccount;
      final s = await _store(user: () => user, prefs: {'akarat.tour.explore': false});
      await s.store.markDone(TourId.explore);
      user = fakeUser(
        id: '55555555-5555-4555-8555-555555555555',
        metadata: const {
          'full_name': 'Rami',
          'tour_pending': true,
          'tours_done': ['explore'],
        },
      );
      expect(s.store.welcomeOwed, isTrue);
    });

    test('offline, the phone keeps the record and the account gets it at the next launch', () async {
      final user = _newAccount;
      final offline = await _store(user: () => user, prefs: {'akarat.tour.explore': false}, offline: true);
      await offline.store.markDone(TourId.explore);
      expect(offline.prefs.tourSeen('explore'), isTrue);
      expect(offline.store.welcomeOwed, isFalse, reason: 'not shown twice while the account is out of date');

      final saves = <Map<String, Object>>[];
      final online = TourStore(
        offline.prefs,
        user: () => user,
        save: (data) async {
          saves.add(data);
          return null;
        },
      );
      await online.sync();
      expect(saves.single, {
        'tours_done': ['explore'],
        'tour_pending': false,
      });
    });

    test('a guest is shown the main tour once, and only after the introduction', () async {
      final s = await _store(prefs: {'akarat.onboarded': false});
      expect(s.store.shouldStart(TourId.explore), isFalse, reason: 'the introduction comes first');
      await s.prefs.setOnboarded();
      expect(s.store.shouldStart(TourId.explore), isTrue);
      await s.store.markDone(TourId.explore);
      expect(s.store.shouldStart(TourId.explore), isFalse);
      expect(s.saves, isEmpty, reason: 'a guest has no account to write to');
    });

    test('signing up after the guest tour: a welcome is owed, and the tours seen come along', () async {
      final s = await _store(prefs: {'akarat.tour.explore': true, 'akarat.tour.map': true});
      expect(s.store.signUpData(), {
        'tour_pending': true,
        'tours_done': ['explore', 'map'],
      });
    });

    test('a tour cut short picks up where it was; the welcome keeps its own place', () async {
      final s = await _store();
      await s.store.setStep(TourId.explore, 3);
      await s.store.setStep(TourId.explore, 1, welcome: true);
      expect(s.store.step(TourId.explore), 3);
      expect(s.store.step(TourId.explore, welcome: true), 1);
      await s.store.markDone(TourId.explore);
      expect(s.store.step(TourId.explore), 0);
      expect(s.store.step(TourId.explore, welcome: true), 0);
    });
  });

  group('The welcome tour', () {
    testWidgets('a new account is welcomed by name, then walked through the app', (tester) async {
      final (overrides, saves) = await _deps(user: _newAccount, prefs: {'akarat.tour.explore': false});
      await pumpScreen(tester, _homeWithTabs(signedIn: true), overrides: overrides);
      await _settle(tester);
      expect(find.text('Welcome, Lina'), findsOneWidget);
      expect(find.textContaining('one-minute look'), findsOneWidget);
      expect(find.text('1 of 8'), findsOneWidget);
      for (final title in [
        'Just describe it',
        'Buying or renting?',
        'Pick a city',
        'See it on a map',
        'Ask for it',
        'Keep the ones you like',
        'List your own property',
      ]) {
        await _next(tester);
        expect(find.text(title), findsOneWidget);
      }
      expect(find.textContaining('From Profile'), findsOneWidget, reason: 'signed in, the last step is Profile');
      expect(saves, isEmpty, reason: 'nothing is recorded until it ends');
      await _next(tester, label: 'Got it');
      expect(find.text('List your own property'), findsNothing);
      expect(saves.single['tour_pending'], isFalse);
      expect(saves.single['tours_done'], contains('explore'));
    });

    testWidgets('after the guest tour, a new account is shown just what it adds', (tester) async {
      final (overrides, saves) = await _deps(user: _newAccount, prefs: {'akarat.tour.explore': true});
      await pumpScreen(tester, _homeWithTabs(signedIn: true), overrides: overrides);
      await _settle(tester);
      expect(find.text('Welcome, Lina'), findsOneWidget);
      expect(find.text("Your account is ready. Here's where to find what it adds."), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      await _next(tester);
      expect(find.text('Keep the ones you like'), findsOneWidget);
      await _next(tester);
      expect(find.text('List your own property'), findsOneWidget);
      await _next(tester, label: 'Got it');
      expect(saves.single['tour_pending'], isFalse);
    });

    testWidgets('an existing account opening the app is not toured', (tester) async {
      for (final user in [
        _oldAccount,
        fakeUser(metadata: const {'tour_pending': false, 'tours_done': []}),
      ]) {
        final (overrides, _) = await _deps(user: user, prefs: {'akarat.tour.explore': false});
        await pumpScreen(tester, _homeWithTabs(signedIn: true), overrides: overrides);
        await _settle(tester);
        expect(find.text('Skip tour'), findsNothing, reason: '${user.userMetadata}');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('closed mid-tour, it opens again at the same step', (tester) async {
      final (overrides, saves) = await _deps(user: _newAccount, prefs: {'akarat.tour.explore': false});
      await pumpScreen(tester, _homeWithTabs(signedIn: true), overrides: overrides);
      await _settle(tester);
      await _next(tester);
      await _next(tester);
      expect(find.text('3 of 8'), findsOneWidget);

      // The app is closed...
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(saves, isEmpty, reason: 'not finished, so not recorded');

      // ...and opened again.
      await pumpScreen(tester, _homeWithTabs(signedIn: true), overrides: overrides);
      await _settle(tester);
      expect(find.text('3 of 8'), findsOneWidget);
      expect(find.text('Buying or renting?'), findsOneWidget);
      await _next(tester, label: 'Back');
      await _next(tester, label: 'Back');
      expect(find.text('Welcome, Lina'), findsOneWidget, reason: 'and the welcome is still there to go back to');
    });

    testWidgets('switching language mid-tour switches the tour', (tester) async {
      final (overrides, _) = await _deps(prefs: {'akarat.tour.explore': false});
      await pumpScreen(tester, _homeWithTabs(signedIn: false), overrides: overrides);
      await _settle(tester);
      await _next(tester);
      expect(find.text('Buying or renting?'), findsOneWidget);
      expect(_position(tester), (2, 7));

      await pumpScreen(tester, _homeWithTabs(signedIn: false), overrides: overrides, lang: 'ar');
      await tester.pumpAndSettle();
      expect(find.text('شراء أم إيجار؟'), findsOneWidget);
      expect(find.text('تخطَّ الجولة'), findsOneWidget);
      expect(_position(tester), (2, 7), reason: 'same place in the tour');
      expect(Directionality.of(tester.element(_card())), TextDirection.rtl);
      await _next(tester, label: 'التالي');
      expect(find.text('اختر مدينة'), findsOneWidget);
    });

    testWidgets('turning the phone mid-tour keeps the card on screen and off the control', (tester) async {
      final (overrides, _) = await _deps(prefs: {'akarat.tour.explore': false});
      await pumpScreen(tester, _homeWithTabs(signedIn: false), overrides: overrides);
      await _settle(tester);
      for (var i = 0; i < 5; i++) {
        await _next(tester);
      }
      expect(find.text('Keep the ones you like'), findsOneWidget);
      final targets = ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).read(tourTargetsProvider);

      for (final size in [const Size(844, 390), const Size(390, 844)]) {
        tester.view.physicalSize = size * 3;
        await tester.pumpAndSettle();
        final card = tester.getRect(_card());
        final screen = (Offset.zero & size).inflate(0.5);
        expect(screen.contains(card.topLeft) && screen.contains(card.bottomRight), isTrue, reason: '$card in $size');
        final saved = tester.getRect(find.byKey(targets.navSaved));
        expect(card.overlaps(saved), isFalse, reason: 'the card leaves the Saved tab in view ($size)');
      }
    });

    testWidgets('Skip, the back gesture and Got it each end it; a page taking over does not', (tester) async {
      final a = GlobalKey();
      final b = GlobalKey();
      final router = await pumpRouted(tester, [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Column(
              children: [
                SizedBox(key: a, width: 100, height: 40),
                SizedBox(key: b, width: 100, height: 40),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/other',
          builder: (_, _) => const Scaffold(body: Text('Another page')),
        ),
      ], overrides: await TestDeps().overrides());
      Future<CoachOutcome> start() => showCoachMarks(tester.element(find.byKey(a)), [
        CoachStep(target: a, title: (_) => 'First', body: (_) => 'One.'),
        CoachStep(target: b, title: (_) => 'Second', body: (_) => 'Two.'),
      ]);

      var outcome = start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip tour'));
      await tester.pumpAndSettle();
      expect(await outcome, CoachOutcome.skipped);

      outcome = start();
      await tester.pumpAndSettle();
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      expect(await outcome, CoachOutcome.skipped);

      outcome = start();
      await tester.pumpAndSettle();
      await _next(tester);
      await _next(tester, label: 'Got it');
      expect(await outcome, CoachOutcome.finished);

      // A link or a notification replaces the page under the tour.
      outcome = start();
      await tester.pumpAndSettle();
      router.go('/other');
      await tester.pumpAndSettle();
      expect(find.text('Another page'), findsOneWidget);
      expect(find.text('First'), findsNothing);
      expect(await outcome, CoachOutcome.interrupted);
    });

    testWidgets('replayed from Profile → Guides, from the start and without the welcome', (tester) async {
      final (overrides, saves) = await _deps(user: fakeUser(metadata: const {'tour_pending': false}));
      await pumpRouted(
        tester,
        [
          GoRoute(path: Routes.home, builder: (_, _) => _homeWithTabs(signedIn: true)),
          GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
        ],
        overrides: overrides,
        initial: Routes.profile,
      );
      await tester.scrollUntilVisible(find.text('Finding a property'), 200);
      // Whole, not just its top edge, so the tap lands on it.
      await tester.ensureVisible(find.text('Finding a property'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finding a property'));
      // On to Home first; the tour waits for the page to settle.
      await tester.pumpAndSettle();
      await _settle(tester);
      expect(find.text('Just describe it'), findsOneWidget);
      expect(find.text('1 of 7'), findsOneWidget);
      expect(find.textContaining('Welcome'), findsNothing);
      await tester.tap(find.text('Skip tour'));
      await tester.pumpAndSettle();
      expect(saves.single['tours_done'], contains('explore'));
    });
  });

  group('The listing tour', () {
    testWidgets('the first listing opened explains its photos, saving and contacting the owner', (tester) async {
      final row = listing(
        owner: '99999999-9999-4999-8999-999999999999',
        images: const [
          {'url': 'https://example.invalid/1.jpg'},
          {'url': 'https://example.invalid/2.jpg'},
        ],
      );
      final (overrides, _) = await _deps(rows: [row], prefs: {'akarat.tour.property': false});
      await pumpScreen(
        tester,
        // Photos never arrive in tests: with motion off, their loading
        // shimmer holds still and the screen can settle.
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: PropertyDetailsScreen(id: row.id, initial: row),
          ),
        ),
        overrides: overrides,
      );
      await _settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Every photo'), findsOneWidget);
      await _next(tester);
      expect(find.text('Save it for later'), findsOneWidget);
      await _next(tester);
      expect(find.text('Contact the owner'), findsOneWidget);
      await _next(tester, label: 'Got it');
      final prefs = ProviderScope.containerOf(tester.element(find.byType(PropertyDetailsScreen)))
          .read(preferencesProvider);
      expect(prefs.tourSeen('property'), isTrue);
    });
  });

  group('Tour cards stay on screen', () {
    const portrait = Size(390, 844);
    const landscape = Size(844, 390);
    const tablet = Size(820, 1180);

    EdgeInsets insets(Size size) => size.shortestSide >= 600
        ? const EdgeInsets.only(top: 24, bottom: 20)
        : size.width > size.height
        ? const EdgeInsets.only(left: 47, right: 47, bottom: 21)
        : const EdgeInsets.only(top: 47, bottom: 34);

    for (final (lang, size, scale) in [
      ('en', portrait, 1.0),
      ('en', portrait, 1.6),
      ('ar', portrait, 1.6),
      ('en', landscape, 1.0),
      ('en', landscape, 1.6),
      ('ar', landscape, 1.6),
      ('en', tablet, 1.0),
      ('ar', tablet, 1.3),
    ]) {
      testWidgets('$lang, ${size.width.round()}×${size.height.round()}, text ×$scale', (tester) async {
        final i = insets(size);
        tester.view.padding = FakeViewPadding(
          left: i.left * 3,
          top: i.top * 3,
          right: i.right * 3,
          bottom: i.bottom * 3,
        );
        tester.view.viewPadding = tester.view.padding;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (overrides, _) = await _deps(user: _newAccount, prefs: {'akarat.tour.explore': false});
        await pumpScreen(tester, _homeWithTabs(signedIn: true), overrides: overrides, lang: lang, size: size);
        await _settle(tester);

        final safe = Rect.fromLTRB(i.left, i.top, size.width - i.right, size.height - i.bottom).inflate(0.5);
        while (true) {
          final (at, of) = _position(tester);
          final card = tester.getRect(_card());
          expect(safe.contains(card.topLeft) && safe.contains(card.bottomRight), isTrue, reason: 'step $at: $card');
          if (at == of) break;
          await _next(tester, label: lang == 'ar' ? 'التالي' : 'Next');
          expect(_position(tester).$1, at + 1, reason: 'Next, reachable and working, moves on from step $at');
        }
        expect(_position(tester).$2, greaterThanOrEqualTo(6), reason: 'the controls it explains are on screen');
      });
    }
  });
}
