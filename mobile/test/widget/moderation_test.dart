import 'dart:io';

import 'package:akarat/app/localization/gen/app_localizations.dart';
import 'package:akarat/app/router/routes.dart';
import 'package:akarat/core/widgets/buttons.dart';
import 'package:akarat/features/profile/profile_screen.dart';
import 'package:akarat/features/property_details/property_details_screen.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/models/listing_filters.dart';
import 'package:akarat/shared/repositories/listings_repository.dart';
import 'package:akarat/shared/repositories/reports_repository.dart';
import 'package:akarat/shared/services/hidden_owners.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Another account's id: the listings below are theirs, not the reader's.
const _other = '33333333-3333-4333-8333-333333333333';

final _en = lookupAppLocalizations(const Locale('en'));

/// Records reports, and answers with [error] when given one.
class _FakeReports extends Fake implements ReportsRepository {
  _FakeReports({this.error});
  final Object? error;
  final sent = <(String, ReportReason, String?)>[];

  @override
  Future<void> reportListing(String propertyId, ReportReason reason, {String? details}) async {
    sent.add((propertyId, reason, details));
    if (error != null) throw error!;
  }
}

/// A listing's page over a page it came from, under a real router.
Future<void> _pumpDetails(
  WidgetTester tester,
  Listing row, {
  User? user,
  Map<String, Object> prefs = TestDeps.seen,
  List<Override> extra = const [],
}) async {
  final deps = TestDeps(listings: FakeListingsRepository(rows: [row]));
  await pumpRouted(
    tester,
    [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('before')),
        routes: [GoRoute(path: 'p', builder: (_, _) => PropertyDetailsScreen(id: row.id, initial: row))],
      ),
      GoRoute(path: Routes.signIn, builder: (_, _) => const Scaffold(body: Text('sign-in page'))),
    ],
    overrides: [...await deps.overrides(user: user, prefs: prefs), ...extra],
    initial: '/p',
  );
}

Future<void> _openReportFromPage(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text(_en.reportListing), 400, scrollable: find.byType(Scrollable).first);
  // Built is not on screen: the page builds all of itself at once.
  await tester.ensureVisible(find.text(_en.reportListing));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.reportListing));
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

void main() {
  group('A listing’s More', () {
    testWidgets('on someone else’s listing: report it, or hide its advertiser', (tester) async {
      await _pumpDetails(tester, listing(owner: _other), user: fakeUser());
      await tester.tap(find.byTooltip(_en.detailsMore));
      await tester.pumpAndSettle();
      expect(find.text(_en.reportListing), findsWidgets);
      expect(find.text(_en.hideAdvertiser), findsOneWidget);
    });

    testWidgets('never on your own listing', (tester) async {
      final row = listing();
      await _pumpDetails(tester, row, user: fakeUser());
      expect(find.byTooltip(_en.detailsMore), findsNothing);
      // Down to the reference line, where the report link would be.
      await tester.scrollUntilVisible(
        find.textContaining(row.id.substring(0, 8)),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(_en.reportListing), findsNothing);
    });
  });

  group('Report this listing', () {
    testWidgets('signed out: asked to sign in first, and nothing is sent', (tester) async {
      final reports = _FakeReports();
      await _pumpDetails(tester, listing(owner: _other), extra: [reportsRepositoryProvider.overrideWithValue(reports)]);
      await _openReportFromPage(tester);
      expect(find.text(_en.reportSignIn), findsOneWidget);
      expect(find.text('sign-in page'), findsOneWidget);
      expect(reports.sent, isEmpty);
    });

    testWidgets('goes with its reason and words, and says thanks', (tester) async {
      final reports = _FakeReports();
      final row = listing(owner: _other);
      await _pumpDetails(tester, row, user: fakeUser(), extra: [reportsRepositoryProvider.overrideWithValue(reports)]);
      await _openReportFromPage(tester);
      final send = find.widgetWithText(BusyButton, _en.reportSend);
      expect(tester.widget<BusyButton>(send).onPressed, isNull, reason: 'not before a reason is chosen');
      await tester.tap(find.text(_en.reportReasonScam));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'The photos are from another listing');
      await tester.tap(send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(reports.sent, [(row.id, ReportReason.scam, 'The photos are from another listing')]);
      expect(find.text(_en.reportThanks), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('before migration 0015, the report goes by email, written out', (tester) async {
      final opened = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          opened.add('${(call.arguments as Map)['url']}');
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        ),
      );
      final row = listing(owner: _other);
      await _pumpDetails(
        tester,
        row,
        user: fakeUser(),
        extra: [reportsRepositoryProvider.overrideWithValue(_FakeReports(error: const ReportsUnavailable()))],
      );
      await _openReportFromPage(tester);
      await tester.tap(find.text(_en.reportReasonOffensive));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(BusyButton, _en.reportSend));
      await tester.pumpAndSettle();
      expect(opened.single, startsWith('mailto:hello@akarat.ai'));
      expect(Uri.decodeFull(opened.single), contains(row.id));
      expect(Uri.decodeFull(opened.single), contains('offensive'));
      expect(find.text(_en.reportByEmail('hello@akarat.ai')), findsOneWidget);
    });
  });

  group('Hide this advertiser', () {
    testWidgets('after confirming: their listings are left out, kept on the device, and the page closes', (
      tester,
    ) async {
      await _pumpDetails(tester, listing(owner: _other), user: fakeUser());
      final container = _container(tester, PropertyDetailsScreen);
      await tester.tap(find.byTooltip(_en.detailsMore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.hideAdvertiser));
      await tester.pumpAndSettle();
      expect(find.text(_en.hideAdvertiserTitle), findsOneWidget);
      await tester.tap(find.text(_en.hideAdvertiserAction));
      await tester.pumpAndSettle();
      expect(container.read(hiddenOwnersProvider), {_other});
      expect(container.read(preferencesProvider).hiddenOwners, [_other]);
      expect(find.text('before'), findsOneWidget);
    });

    testWidgets('Profile shows how many, and brings them back', (tester) async {
      await pumpScreen(
        tester,
        const ProfileScreen(),
        overrides: await TestDeps().overrides(
          prefs: {
            ...TestDeps.seen,
            'akarat.hiddenOwners': [_other],
          },
        ),
      );
      final label = _en.profileHiddenAdvertisers(1);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(label), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.showHiddenAction));
      await tester.pumpAndSettle();
      expect(_container(tester, ProfileScreen).read(hiddenOwnersProvider), isEmpty);
      expect(find.text(_en.showHiddenDone), findsOneWidget);
      expect(find.text(label), findsNothing);
    });

    test('keeps only real account ids, once each', () async {
      SharedPreferences.setMockInitialValues({
        'akarat.hiddenOwners': [_other, 'not-an-id'],
      });
      final prefs = Preferences(await SharedPreferences.getInstance());
      final container = ProviderContainer(overrides: [preferencesProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      expect(container.read(hiddenOwnersProvider), {_other});
      await container.read(hiddenOwnersProvider.notifier).hide(_other);
      await container.read(hiddenOwnersProvider.notifier).hide('); drop table');
      expect(container.read(hiddenOwnersProvider), {_other});
      await container.read(hiddenOwnersProvider.notifier).showAll();
      expect(prefs.hiddenOwners, isEmpty);
    });
  });

  group('The database side', () {
    test('hidden advertisers are left out by each public query itself', () async {
      final urls = <Uri>[];
      final client = SupabaseClient(
        'https://db.example.invalid',
        'publishable-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((req) async {
          urls.add(req.url);
          return http.Response('[]', 200, request: req, headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(client.dispose);
      final repo = ListingsRepository(client, hiddenOwners: {_other});
      await repo.recent();
      await repo.featured();
      await repo.mapListings(const ListingFilters());
      // Nothing in the city, so it asks a second time, more widely.
      await repo.similar(id: '11111111-1111-4111-8111-111111111111', deal: DealType.sale, type: 'apartment');
      await repo.byIds(['11111111-1111-4111-8111-111111111111']);
      expect(urls, hasLength(6));
      for (final u in urls) {
        // Quoted by the client; PostgREST reads it the same.
        expect(u.queryParameters['owner_id'], 'not.in.("$_other")', reason: '$u');
      }
      urls.clear();
      await ListingsRepository(client).recent();
      expect(urls.single.queryParameters.containsKey('owner_id'), isFalse, reason: 'nothing hidden, nothing added');
    });

    test('the reasons the app sends are the ones migration 0015 accepts', () {
      final sql = File('../supabase/migrations/0015_listing_reports.sql').readAsStringSync();
      const start = 'check (reason in (';
      final from = sql.indexOf(start) + start.length;
      final accepted = sql
          .substring(from, sql.indexOf(')', from))
          .split(',')
          .map((s) => s.trim().replaceAll("'", ''))
          .toSet();
      expect({for (final r in ReportReason.values) r.stored}, accepted);
    });
  });
}
