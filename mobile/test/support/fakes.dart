import 'dart:async';
import 'dart:io';

import 'package:akarat/core/utils/payload_codec.dart';
import 'package:akarat/features/ai_search/data/search_repository.dart';
import 'package:akarat/features/ai_search/voice/speech_service.dart';
import 'package:akarat/shared/models/account_models.dart';
import 'package:akarat/shared/models/listing.dart';
import 'package:akarat/shared/models/listing_filters.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:akarat/shared/repositories/account_repositories.dart';
import 'package:akarat/shared/repositories/favorites_repository.dart';
import 'package:akarat/shared/repositories/listings_repository.dart';
import 'package:akarat/shared/repositories/media_repository.dart';
import 'package:akarat/shared/repositories/translation_repository.dart';
import 'package:akarat/shared/services/activity.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A listing row shaped exactly like PostgREST returns it.
Listing listing({
  String id = '11111111-1111-4111-8111-111111111111',
  String owner = '22222222-2222-4222-8222-222222222222',
  String status = 'active',
  String deal = 'sale',
  String type = 'apartment',
  String? city = 'amman',
  String? hood = 'abdoun',
  int price = 150000,
  int? beds = 3,
  int? baths = 2,
  int? area = 180,
  String titleEn = 'Bright corner apartment',
  String? titleAr = 'شقة زاوية مشمسة',
  String phone = '0791234567',
  List<String> amenities = const ['parking', 'elevator'],
  double? lat = 31.936,
  double? lng = 35.879,
  String precision = 'approximate',
  bool verified = false,
  List<Map<String, Object?>> images = const [],
}) {
  final packed = PayloadCodec.pack({
    'amenities': amenities,
    'description_en': 'A quiet street, five minutes from Abdoun Circle.',
    'description_ar': 'شارع هادئ على بعد خمس دقائق من دوار عبدون.',
    'images': images,
    'contact': {'phone': phone, 'whatsapp': true, 'messaging': true},
  });
  return Listing.fromRow({
    'id': id,
    'owner_id': owner,
    'status': status,
    'deal': deal,
    'property_type': type,
    'city_id': city,
    'neighborhood_id': hood,
    'lat': lat,
    'lng': lng,
    'price_jod': price,
    'bedrooms': beds,
    'bathrooms': baths,
    'area_sqm': area,
    'title_en': titleEn,
    'title_ar': titleAr,
    'verified': verified,
    'payload_gz': packed.payloadGz,
    'created_at': '2026-09-20T10:00:00Z',
    'updated_at': '2026-09-20T10:00:00Z',
    'location_precision': precision,
  });
}

class FakeListingsRepository extends Fake implements ListingsRepository {
  FakeListingsRepository({this.rows = const [], this.error, this.pending = false});
  List<Listing> rows;
  Object? error;

  /// Reads never complete: the screen stays in its loading state.
  bool pending;
  final _never = Completer<Never>();
  final created = <Map<String, Object?>>[];
  final createdPayloads = <ListingPayload>[];
  final updated = <String, Map<String, Object?>>{};
  final exactSaved = <String, ({double lat, double lng, String? address})>{};
  final statusChanges = <String, ListingStatus>{};
  final deleted = <String>[];

  Future<void> _maybeThrow() async {
    if (pending) await _never.future;
    if (error != null) throw error!;
  }

  @override
  Future<List<Listing>> recent({DealType? deal, String? cityId, int limit = 10}) async {
    await _maybeThrow();
    return rows.where((r) => deal == null || r.deal == deal).toList();
  }

  @override
  Future<List<Listing>> featured({DealType? deal, String? cityId, int limit = 8}) async {
    await _maybeThrow();
    return rows.where((r) => r.featured).toList();
  }

  @override
  Future<ListingPage> browse(ListingFilters f, {int page = 0}) async {
    await _maybeThrow();
    final matching = rows.where((r) => f.deal == null || r.deal == f.deal).toList();
    final start = page * ListingsRepository.pageSize;
    final slice = matching.skip(start).take(ListingsRepository.pageSize).toList();
    return ListingPage(items: slice, total: matching.length, page: page);
  }

  @override
  Future<Listing?> byId(String id) async {
    await _maybeThrow();
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Future<List<Listing>> byIds(List<String> ids) async => [for (final id in ids) ...rows.where((r) => r.id == id)];

  @override
  Future<List<Listing>> similar({
    required String id,
    required DealType deal,
    required String type,
    String? cityId,
    int limit = 6,
  }) async => rows.where((r) => r.id != id).toList();

  @override
  Future<List<Listing>> mine() async => rows;

  @override
  Future<List<Listing>> mapListings(ListingFilters f, {int limit = 500}) async {
    await _maybeThrow();
    return rows.where((r) => f.deal == null || r.deal == f.deal).toList();
  }

  @override
  Future<Listing> create(Map<String, Object?> columns, ListingPayload payload) async {
    await _maybeThrow();
    created.add(columns);
    createdPayloads.add(payload);
    return listing(id: '33333333-3333-4333-8333-333333333333', status: columns['status']! as String);
  }

  @override
  Future<Listing> update(String id, Map<String, Object?> columns, ListingPayload payload) async {
    await _maybeThrow();
    updated[id] = columns;
    return rows.firstWhere((r) => r.id == id);
  }

  @override
  Future<void> setStatus(String id, ListingStatus status) async => statusChanges[id] = status;

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  Future<void> saveExactLocation(
    String propertyId, {
    required double lat,
    required double lng,
    String? address,
  }) async => exactSaved[propertyId] = (lat: lat, lng: lng, address: address);

  @override
  Future<({double lat, double lng, String? address})?> exactLocation(String propertyId) async => exactSaved[propertyId];
}

class FakeMediaRepository extends Fake implements MediaRepository {
  int uploads = 0;
  int attempts = 0;

  /// Fails the Nth upload attempt (1-based) as if the connection dropped.
  int? failOnAttempt;
  final removed = <String>[];

  @override
  Future<MediaItem> upload(File file, {required bool video}) async {
    attempts++;
    if (attempts == failOnAttempt) throw const SocketException('offline');
    uploads++;
    return MediaItem(
      url: 'https://cdn.invalid/u/$uploads.jpg',
      path: 'u/$uploads.jpg',
      kind: video ? MediaKind.video : MediaKind.image,
    );
  }

  @override
  Future<void> remove(List<String> paths) async => removed.addAll(paths);
}

/// Records what the app would have counted for the admin panel.
class FakeActivity extends Fake implements Activity {
  int beats = 0;
  final views = <String>[];

  @override
  Future<void> heartbeat() async => beats++;

  @override
  Future<void> recordView(String propertyId) async => views.add(propertyId);
}

/// Translates by tagging the text with its target language, so a test can see
/// which way it went. [available] false answers like a deployment without the
/// route or the key: null, every time.
class FakeTranslationRepository extends Fake implements TranslationRepository {
  FakeTranslationRepository({this.available = false});
  bool available;
  final calls = <({String from, String title, String description})>[];

  @override
  Future<({String title, String description})?> translate({
    required String from,
    String title = '',
    String description = '',
  }) async {
    calls.add((from: from, title: title, description: description));
    if (!available) return null;
    final to = from == 'en' ? 'ar' : 'en';
    String t(String s) => s.isEmpty ? '' : '[$to] $s';
    return (title: t(title), description: t(description));
  }
}

class FakeFavoritesRepository extends Fake implements FavoritesRepository {
  FakeFavoritesRepository({this.available = true});
  bool available;
  bool failWrites = false;
  final stored = <String>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<String>> list() async => List.of(stored);

  @override
  Future<void> add(String propertyId) async {
    if (failWrites) throw const SocketException('offline');
    stored.insert(0, propertyId);
  }

  @override
  Future<void> addAll(Iterable<String> propertyIds) async => stored.insertAll(0, propertyIds);

  @override
  Future<void> remove(String propertyId) async {
    if (failWrites) throw const SocketException('offline');
    stored.remove(propertyId);
  }
}

class FakeSearchRepository extends Fake implements SearchRepository {
  FakeSearchRepository(this.outcome);
  SearchOutcome Function(SearchConstraints) outcome;
  final calls = <SearchConstraints>[];

  @override
  Future<SearchOutcome> search(SearchConstraints c, {CancelToken? cancelToken, DateTime? now}) async {
    calls.add(c);
    return outcome(c);
  }
}

class FakeSavedSearchesRepository extends Fake implements SavedSearchesRepository {
  FakeSavedSearchesRepository([List<SavedSearch> rows = const []]) : rows = [...rows];
  final List<SavedSearch> rows;
  final deleted = <String>[];

  @override
  Future<List<SavedSearch>> list() async => List.of(rows);

  @override
  Future<SavedSearch> create(String label, SearchConstraints constraints) async {
    final row = SavedSearch(
      id: 'saved-${rows.length + 1}',
      label: label,
      constraints: constraints,
      createdAt: DateTime(2026, 10),
    );
    rows.add(row);
    return row;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    rows.removeWhere((r) => r.id == id);
  }
}

class FakeProfileRepository extends Fake implements ProfileRepository {
  FakeProfileRepository([this.profile]);
  Profile? profile;

  @override
  Future<Profile?> mine() async => profile;

  @override
  Future<void> update({String? fullName, String? phone, String? locale}) async {}
}

class FakeInquiriesRepository extends Fake implements InquiriesRepository {
  FakeInquiriesRepository({this.inbox = const []});
  final List<Inquiry> inbox;
  final outbox = <Map<String, String?>>[];

  @override
  Future<void> send({
    required String propertyId,
    required String ownerId,
    required String name,
    required String message,
    String? email,
    String? phone,
  }) async => outbox.add({
    'propertyId': propertyId,
    'ownerId': ownerId,
    'name': name,
    'message': message,
    'email': email,
    'phone': phone,
  });

  @override
  Future<List<Inquiry>> received() async => inbox;

  @override
  Future<List<Inquiry>> sent() async => const [];
}

/// A speech recogniser the test speaks through.
class FakeSpeechService implements SpeechService {
  FakeSpeechService({this.ready = true, this.failure, this.locales = const ['en_US', 'ar_JO']});
  final bool ready;
  final SpeechFailure? failure;
  final List<String> locales;
  final listenedIn = <String>[];
  void Function(String, bool)? _words;
  void Function(double)? _level;
  void Function(SpeechFailure)? _fail;

  @override
  SpeechFailure? get lastFailure => failure;

  @override
  Future<bool> prepare() async => ready;

  @override
  Future<List<String>> localeIds() async => locales;

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onWords,
    required void Function(double level) onLevel,
    required void Function(SpeechFailure failure) onFailure,
    required void Function() onDone,
  }) async {
    listenedIn.add(localeId);
    _words = onWords;
    _level = onLevel;
    _fail = onFailure;
  }

  void say(String words, {bool done = false}) => _words?.call(words, done);
  void level(double db) => _level?.call(db);
  void fail(SpeechFailure f) => _fail?.call(f);

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}
