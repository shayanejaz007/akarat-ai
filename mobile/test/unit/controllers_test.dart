import 'package:akarat/core/errors/app_failure.dart';
import 'package:akarat/core/utils/geo.dart';
import 'package:akarat/features/ai_search/data/search_repository.dart';
import 'package:akarat/features/ai_search/domain/search_item.dart';
import 'package:akarat/features/ai_search/presentation/ai_search_controller.dart';
import 'package:akarat/features/explore/explore_controller.dart';
import 'package:akarat/features/favorites/favorites_controller.dart';
import 'package:akarat/features/listings/application/listing_wizard_controller.dart';
import 'package:akarat/features/listings/domain/listing_draft.dart';
import 'package:akarat/features/settings/settings_controller.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/models/listing_filters.dart';
import 'package:akarat/shared/services/preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;

import '../support/fakes.dart';
import '../support/harness.dart';

Future<ProviderContainer> container(TestDeps deps, {bool signedIn = false, Map<String, Object>? prefs}) async {
  final c = ProviderContainer(
    overrides: await deps.overrides(
      user: signedIn ? fakeUser() : null,
      prefs: prefs ?? const {'akarat.onboarded': true},
    ),
    retry: (_, _) => null,
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoritesController', () {
    test('a guest saves on the device', () async {
      final deps = TestDeps();
      final c = await container(deps);
      await c.read(favoritesProvider.notifier).sync();
      expect(await c.read(favoritesProvider.notifier).toggle('a'), isTrue);
      expect(c.read(favoritesProvider).ids, ['a']);
      expect(c.read(favoritesProvider).mode, FavoritesMode.device);
      expect(c.read(preferencesProvider).localFavorites, ['a']);
      expect(await c.read(favoritesProvider.notifier).toggle('a'), isFalse);
      expect(c.read(favoritesProvider).ids, isEmpty);
    });

    test('signing in carries guest favourites into the account, then clears the device', () async {
      final deps = TestDeps(favorites: FakeFavoritesRepository(available: true)..stored.add('remote'));
      final c = await container(
        deps,
        signedIn: true,
        prefs: {
          'akarat.onboarded': true,
          'akarat.favorites.local': ['guest'],
        },
      );
      await c.read(favoritesProvider.notifier).sync();
      final s = c.read(favoritesProvider);
      expect(s.mode, FavoritesMode.account);
      expect(s.ids, containsAll(['guest', 'remote']));
      expect(c.read(preferencesProvider).localFavorites, isEmpty);
    });

    test('a failed write rolls back and reports the failure', () async {
      final repo = FakeFavoritesRepository(available: true)..failWrites = true;
      final c = await container(TestDeps(favorites: repo), signedIn: true);
      await c.read(favoritesProvider.notifier).sync();
      await expectLater(c.read(favoritesProvider.notifier).toggle('x'), throwsA(anything));
      expect(c.read(favoritesProvider).ids, isNot(contains('x')));
    });

    test('without migration 0014 the account falls back to the device and says so', () async {
      final c = await container(TestDeps(favorites: FakeFavoritesRepository(available: false)), signedIn: true);
      await c.read(favoritesProvider.notifier).sync();
      expect(c.read(favoritesProvider).mode, FavoritesMode.deviceFallback);
    });
  });

  group('ListingWizardController.save', () {
    test('an approximate pin is published blurred, the exact one kept owner-only', () async {
      final deps = TestDeps();
      final c = await container(deps, signedIn: true);
      c.listen(listingWizardProvider(null), (_, _) {});
      final ctrl = c.read(listingWizardProvider(null).notifier);
      ctrl.update(
        (d) => d.copyWith(
          price: '150,000',
          titleEn: 'Flat',
          bedrooms: '3',
          lat: 31.936,
          lng: 35.879,
          address: '12 Abdoun St',
          precision: LocationPrecision.approximate,
        ),
      );
      final saved = await ctrl.save(publish: true);
      expect(saved, isNotNull);

      final cols = deps.listings.created.single;
      final blurred = Geo.blur(31.936, 35.879);
      expect(cols['lat'], blurred.lat);
      expect(cols['lng'], blurred.lng);
      expect(cols['address'], isNull, reason: 'an address next to a blurred point gives the blur away');
      expect(cols['status'], 'active');
      expect(cols['price_jod'], 150000);
      expect(cols['bedrooms'], 3);
      expect(cols['title_ar'], 'Flat', reason: 'the missing title falls back to the other');
      expect(cols.containsKey('owner_id'), isFalse, reason: 'ownership comes from the session in the repository');
      expect(deps.listings.exactSaved[saved!.id]?.lat, 31.936);
      expect(c.read(preferencesProvider).listingDraft, isNull, reason: 'a published listing clears the local draft');
    });

    test('an exact pin publishes the point and the address', () async {
      final deps = TestDeps();
      final c = await container(deps, signedIn: true);
      c.listen(listingWizardProvider(null), (_, _) {});
      final ctrl = c.read(listingWizardProvider(null).notifier);
      ctrl.update(
        (d) => d.copyWith(
          price: '500',
          titleAr: 'شقة',
          lat: 31.9,
          lng: 35.9,
          address: 'Rainbow St',
          precision: LocationPrecision.exact,
        ),
      );
      await ctrl.save(publish: false);
      final cols = deps.listings.created.single;
      expect(cols['lat'], 31.9);
      expect(cols['address'], 'Rainbow St');
      expect(cols['status'], 'draft');
    });

    test('nothing is written while required fields are missing', () async {
      final deps = TestDeps();
      final c = await container(deps, signedIn: true);
      c.listen(listingWizardProvider(null), (_, _) {});
      final ctrl = c.read(listingWizardProvider(null).notifier);
      expect(ctrl.problems(), containsAll([DraftProblem.title, DraftProblem.price]));
      expect(await ctrl.save(publish: true), isNull);
      expect(deps.listings.created, isEmpty);
    });

    test('a failed upload saves nothing, and a retry does not upload twice', () async {
      final deps = TestDeps(media: FakeMediaRepository()..failOnAttempt = 2);
      final c = await container(deps, signedIn: true);
      c.listen(listingWizardProvider(null), (_, _) {});
      final ctrl = c.read(listingWizardProvider(null).notifier);
      ctrl.update(
        (d) => d.copyWith(
          price: '1000',
          titleEn: 'Two photos',
          media: const [
            DraftMedia(localPath: 'a.jpg', kind: MediaKind.image),
            DraftMedia(localPath: 'b.jpg', kind: MediaKind.image),
          ],
        ),
      );
      expect(await ctrl.save(publish: true), isNull);
      expect(deps.listings.created, isEmpty, reason: 'no row may point at files that did not upload');
      expect(AppFailure.from(c.read(listingWizardProvider(null)).error!).kind, FailureKind.network);
      expect(deps.media.uploads, 1);

      expect(await ctrl.save(publish: true), isNotNull);
      expect(deps.media.uploads, 2, reason: 'the first file was already uploaded and is reused');
      expect(deps.listings.createdPayloads.single.media.map((m) => m.path), ['u/1.jpg', 'u/2.jpg']);
    });

    test('editing keeps status untouched and deletes removed files afterwards', () async {
      final existing = listing(
        images: const [
          {'url': 'https://cdn.invalid/x.jpg', 'path': '22222222-2222-4222-8222-222222222222/x.jpg', 'type': 'image'},
        ],
      );
      final deps = TestDeps(listings: FakeListingsRepository(rows: [existing]));
      final c = await container(deps, signedIn: true);
      final provider = listingWizardProvider(existing.id);
      c.listen(provider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final ctrl = c.read(provider.notifier);
      expect(c.read(provider).editing, isTrue);
      ctrl.removeMedia(0);
      await ctrl.save(publish: true);
      final cols = deps.listings.updated[existing.id]!;
      expect(cols.containsKey('status'), isFalse);
      expect(deps.media.removed, ['22222222-2222-4222-8222-222222222222/x.jpg']);
    });
  });

  group('ListingWizardController translation', () {
    Future<(ProviderContainer, ListingWizardController, TestDeps)> wizard({bool available = true}) async {
      final deps = TestDeps(translation: FakeTranslationRepository(available: available));
      final c = await container(deps, signedIn: true);
      c.listen(listingWizardProvider(null), (_, _) {});
      return (c, c.read(listingWizardProvider(null).notifier), deps);
    }

    test('leaving an English field fills the empty Arabic one', () async {
      final (c, ctrl, _) = await wizard();
      ctrl.update((d) => d.copyWith(titleEn: 'Flat in Abdoun', descriptionEn: 'Sunny'));
      await ctrl.autoTranslate('en');
      final s = c.read(listingWizardProvider(null));
      expect(s.draft.titleAr, '[ar] Flat in Abdoun');
      expect(s.draft.descriptionAr, '[ar] Sunny');
      expect(s.translatedInto, 'ar');
      expect(s.translating, isFalse);
    });

    test('never overwrites what the owner typed in the other language', () async {
      final (c, ctrl, deps) = await wizard();
      ctrl.update((d) => d.copyWith(titleEn: 'Flat', titleAr: 'شقة مميزة'));
      await ctrl.autoTranslate('en');
      expect(c.read(listingWizardProvider(null)).draft.titleAr, 'شقة مميزة');
      expect(deps.translation.calls, isEmpty);
    });

    test('a changed source re-fills its own earlier translation', () async {
      final (c, ctrl, deps) = await wizard();
      ctrl.update((d) => d.copyWith(titleAr: 'شقة'));
      await ctrl.autoTranslate('ar');
      await ctrl.autoTranslate('ar');
      expect(deps.translation.calls, hasLength(1), reason: 'the same text is not translated twice');
      ctrl.update((d) => d.copyWith(titleAr: 'فيلا'));
      await ctrl.autoTranslate('ar');
      expect(c.read(listingWizardProvider(null)).draft.titleEn, '[en] فيلا');
    });

    test('saving translates any language still missing', () async {
      final (_, ctrl, deps) = await wizard();
      ctrl.update((d) => d.copyWith(price: '500', cityId: 'amman', titleAr: 'شقة', descriptionEn: 'Quiet street'));
      expect(await ctrl.save(publish: true), isNotNull);
      final cols = deps.listings.created.single;
      expect(cols['title_ar'], 'شقة');
      expect(cols['title_en'], '[en] شقة');
      final payload = deps.listings.createdPayloads.single;
      expect(payload.descriptionAr, '[ar] Quiet street');
      expect(payload.descriptionEn, 'Quiet street');
    });

    test('without translation, saving still works and copies the title', () async {
      final (_, ctrl, deps) = await wizard(available: false);
      ctrl.update((d) => d.copyWith(price: '500', cityId: 'amman', titleEn: 'Flat'));
      expect(await ctrl.save(publish: true), isNotNull);
      expect(deps.listings.created.single['title_ar'], 'Flat');
    });
  });

  group('AiSearchController', () {
    test('a follow-up refines the brief rather than replacing it', () async {
      final repo = FakeSearchRepository((c) => outcomeOf(const []));
      final c = await container(TestDeps(search: repo));
      final ctrl = c.read(aiSearchProvider.notifier);
      await ctrl.submit('apartment for sale in Abdoun under 200k');
      await ctrl.submit('make it 3 bedrooms');
      final s = c.read(aiSearchProvider);
      expect(s.turns, hasLength(2));
      expect(s.constraints!.hood, 'abdoun');
      expect(s.constraints!.beds, 3);
      expect(s.constraints!.budgetMax, 200000);
      expect(s.phase, SearchPhase.done);
      expect(repo.calls, hasLength(2));
    });

    test('removing a chip searches again without it', () async {
      final repo = FakeSearchRepository((c) => outcomeOf(const []));
      final c = await container(TestDeps(search: repo));
      final ctrl = c.read(aiSearchProvider.notifier);
      await ctrl.submit('villa in Amman with a pool');
      await ctrl.setConstraints(c.read(aiSearchProvider).constraints!.copyWith(amenities: const []));
      expect(repo.calls.last.amenities, isEmpty);
    });

    test('being rate limited is a failed search, not an empty one', () async {
      final repo = FakeSearchRepository((c) => throw const AppFailure(FailureKind.rateLimited, status: 429));
      final c = await container(TestDeps(search: repo));
      await c.read(aiSearchProvider.notifier).submit('flat in Khalda');
      final s = c.read(aiSearchProvider);
      expect(s.phase, SearchPhase.failed);
      expect(AppFailure.from(s.error!).kind, FailureKind.rateLimited);
    });

    test('results keep internal and external apart', () async {
      final mine = SearchItem.fromListing(listing());
      const theirs = SearchItem(
        id: 'x-1',
        titleEn: 'Portal flat',
        titleAr: 'Portal flat',
        source: 'opensooq',
        kind: 'known_marketplace',
      );
      final repo = FakeSearchRepository((c) => outcomeOf([RankedResult(mine, 90), const RankedResult(theirs, 60)]));
      final c = await container(TestDeps(search: repo));
      await c.read(aiSearchProvider.notifier).submit('apartment in Abdoun');
      final o = c.read(aiSearchProvider).outcome!;
      expect(o.internal.single.item.id, mine.id);
      expect(o.external.single.item.id, 'x-1');
    });
  });

  group('ExploreController', () {
    test('pages until the database total is reached, without duplicates', () async {
      final rows = [
        for (var i = 0; i < 45; i++) listing(id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
      ];
      final c = await container(TestDeps(listings: FakeListingsRepository(rows: rows)));
      c.listen(exploreProvider, (_, _) {});
      c.read(exploreFiltersProvider.notifier).replace(const ListingFilters(deal: DealType.sale));
      var s = await c.read(exploreProvider.future);
      expect(s.items, hasLength(20));
      expect(s.total, 45);
      await c.read(exploreProvider.notifier).loadMore();
      await c.read(exploreProvider.notifier).loadMore();
      s = c.read(exploreProvider).value!;
      expect(s.items, hasLength(45));
      expect(s.hasMore, isFalse);
      expect(s.items.map((e) => e.id).toSet(), hasLength(45));
    });
  });

  group('LocaleController', () {
    final binding = TestWidgetsFlutterBinding.instance;
    tearDown(binding.platformDispatcher.clearLocaleTestValue);

    test('follows the device language, live, until the reader picks one', () async {
      binding.platformDispatcher.localeTestValue = const Locale('en', 'US');
      final c = await container(TestDeps());
      expect(c.read(localeProvider), const Locale('en'));

      binding.platformDispatcher.localeTestValue = const Locale('ar', 'JO');
      c.read(localeProvider.notifier).followDevice();
      expect(c.read(localeProvider), const Locale('ar'));

      await c.read(localeProvider.notifier).set('en');
      binding.platformDispatcher.localeTestValue = const Locale('ar', 'JO');
      c.read(localeProvider.notifier).followDevice();
      expect(c.read(localeProvider), const Locale('en'), reason: 'the reader chose English');
    });

    test('a device language other than English or Arabic opens in Arabic', () async {
      binding.platformDispatcher.localeTestValue = const Locale('fr', 'FR');
      final c = await container(TestDeps());
      expect(c.read(localeProvider), const Locale('ar'));
    });
  });

  group('ListingDraft', () {
    test('survives a round trip through device storage', () {
      const d = ListingDraft(
        deal: DealType.rent,
        propertyType: 'villa',
        cityId: 'aqaba',
        neighborhoodId: 'talabay',
        price: '900',
        titleAr: 'فيلا',
        amenities: ['pool'],
        lat: 29.4,
        lng: 34.97,
        precision: LocationPrecision.exact,
      );
      final back = ListingDraft.fromJson(d.toJson())!;
      expect(back.toJson(), d.toJson());
      expect(ListingDraft.number('١٢٠٬٠٠٠'), isNull, reason: 'folding happens in the input formatter, not here');
      expect(ListingDraft.number('120,000'), 120000);
    });
  });
}
