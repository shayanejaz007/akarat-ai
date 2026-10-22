import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../core/utils/payload_codec.dart';
import '../models/listing.dart';
import '../models/listing_filters.dart';
import '../services/supabase_providers.dart';

final listingsRepositoryProvider = Provider<ListingsRepository>(
  (ref) => ListingsRepository(ref.watch(supabaseClientProvider)),
);

class ListingPage {
  const ListingPage({required this.items, required this.total, required this.page});
  final List<Listing> items;

  /// Rows matching the filters across all pages, counted by the database.
  final int total;
  final int page;
}

/// Reads and writes `public.properties` with the publishable key, so Row
/// Level Security decides every answer exactly as it does for the website:
///
/// * anyone reads rows whose status is active, sold or rented (0011);
/// * an owner additionally reads and writes rows where owner_id = auth.uid().
///
/// Nothing here can widen that. The `.eq('owner_id', …)` on writes is belt and
/// braces against a bug in this file, not the control itself.
class ListingsRepository {
  ListingsRepository(this._db);
  final SupabaseClient _db;

  static const pageSize = 20;
  static const _int32Max = 2147483647;

  /// price_jod is a Postgres integer. A bound past its range fails the whole
  /// query, so absurd budgets are clamped rather than sent.
  static int _clamp(int v) => v < 0 ? 0 : (v > _int32Max ? _int32Max : v);

  /// Rows the app cannot read at all (no id, say) are left out rather than
  /// failing every other listing on the page with them.
  List<Listing> _rows(List<Map<String, dynamic>> data) {
    final out = <Listing>[];
    for (final r in data) {
      try {
        out.add(Listing.fromRow(Map<String, Object?>.from(r)));
      } on Object catch (e) {
        if (kDebugMode) debugPrint('Skipped unreadable listing ${r['id']}: $e');
      }
    }
    return out;
  }

  String? get _uid => _db.auth.currentUser?.id;

  String _requireUid() {
    final id = _uid;
    if (id == null) throw const AppFailure(FailureKind.unauthorized, detail: 'Not signed in');
    return id;
  }

  /// One page of the public marketplace, filtered and ordered by Postgres.
  /// Public rows matching [f], before ordering and paging.
  PostgrestFilterBuilder<List<Map<String, dynamic>>> _matching(ListingFilters f) {
    final statuses = f.availableOnly ? ['active'] : ListingStatus.public.map((s) => s.name).toList();
    var q = _db.from('properties').select().inFilter('status', statuses);
    if (f.deal case final d?) q = q.eq('deal', d.name);
    if (f.cityId case final c?) q = q.eq('city_id', c);
    if (f.neighborhoodId case final n?) q = q.eq('neighborhood_id', n);
    if (f.type case final t?) q = q.eq('property_type', t);
    // "3 bedrooms" means three or more, as on the website.
    if (f.minBeds case final b?) q = q.gte('bedrooms', b);
    if (f.minBaths case final b?) q = q.gte('bathrooms', b);
    if (f.minPrice case final p?) q = q.gte('price_jod', _clamp(p));
    if (f.maxPrice case final p?) q = q.lte('price_jod', _clamp(p));
    if (f.minArea case final a?) q = q.gte('area_sqm', _clamp(a));
    if (f.maxArea case final a?) q = q.lte('area_sqm', _clamp(a));
    return q;
  }

  /// Every row matching [f], newest first, for the map view: pins for those
  /// with a publishable point, cards for all. One request instead of paging,
  /// capped well above today's inventory.
  Future<List<Listing>> mapListings(ListingFilters f, {int limit = 500}) async {
    try {
      final rows = await _matching(f).order('created_at', ascending: false).limit(limit);
      return _rows(rows);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<ListingPage> browse(ListingFilters f, {int page = 0}) async {
    try {
      final q = _matching(f);
      final ordered = switch (f.sort) {
        ListingSort.newest => q.order('created_at', ascending: false),
        ListingSort.priceAsc => q.order('price_jod', ascending: true).order('created_at', ascending: false),
        ListingSort.priceDesc => q.order('price_jod', ascending: false).order('created_at', ascending: false),
      };
      final from = page * pageSize;
      final res = await ordered.range(from, from + pageSize - 1).count(CountOption.exact);
      return ListingPage(items: _rows(res.data), total: res.count, page: page);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Newest live listings, for Home.
  Future<List<Listing>> recent({DealType? deal, String? cityId, int limit = 10}) async {
    try {
      var q = _db.from('properties').select().eq('status', 'active');
      if (deal != null) q = q.eq('deal', deal.name);
      if (cityId != null) q = q.eq('city_id', cityId);
      return _rows(await q.order('created_at', ascending: false).limit(limit));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Rows an administrator has flagged `featured`. Empty is a real answer:
  /// Home hides the section rather than promoting arbitrary listings.
  Future<List<Listing>> featured({DealType? deal, String? cityId, int limit = 8}) async {
    try {
      var q = _db.from('properties').select().eq('status', 'active').eq('featured', true);
      if (deal != null) q = q.eq('deal', deal.name);
      if (cityId != null) q = q.eq('city_id', cityId);
      return _rows(await q.order('created_at', ascending: false).limit(limit));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// One listing. No status filter here on purpose: RLS returns it when it is
  /// public or when the caller owns it, so an owner can open their own hidden
  /// listing and everyone else gets null.
  Future<Listing?> byId(String id) async {
    if (!_uuid.hasMatch(id)) return null;
    try {
      final row = await _db.from('properties').select().eq('id', id).maybeSingle();
      return row == null ? null : Listing.fromRow(Map<String, Object?>.from(row));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Public rows for a set of ids, in the order given. Missing ids are rows
  /// that were deleted or hidden since they were saved.
  Future<List<Listing>> byIds(List<String> ids) async {
    final valid = ids.where(_uuid.hasMatch).toList();
    if (valid.isEmpty) return const [];
    try {
      final rows = _rows(await _db.from('properties').select().inFilter('id', valid));
      final byId = {for (final r in rows) r.id: r};
      return [for (final id in valid) ?byId[id]];
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Live listings like one being viewed: same deal in the same city, or,
  /// when that city has nothing else, the same deal and type anywhere.
  Future<List<Listing>> similar({
    required String id,
    required DealType deal,
    required String type,
    String? cityId,
    int limit = 6,
  }) async {
    try {
      var q = _db.from('properties').select().eq('status', 'active').eq('deal', deal.name).neq('id', id);
      if (cityId != null) q = q.eq('city_id', cityId);
      final sameCity = _rows(await q.order('created_at', ascending: false).limit(limit));
      if (sameCity.isNotEmpty) return sameCity;
      return _rows(
        await _db
            .from('properties')
            .select()
            .eq('status', 'active')
            .eq('deal', deal.name)
            .eq('property_type', type)
            .neq('id', id)
            .order('created_at', ascending: false)
            .limit(limit),
      );
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Every listing the signed-in user owns, any status, newest first.
  Future<List<Listing>> mine() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      return _rows(await _db.from('properties').select().eq('owner_id', uid).order('created_at', ascending: false));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Inserts a listing owned by the signed-in user.
  ///
  /// owner_id comes from the session, never from [columns]: whatever a caller
  /// passes for it is overwritten here, and the RLS `with check` refuses any
  /// other value independently.
  Future<Listing> create(Map<String, Object?> columns, ListingPayload payload) async {
    final uid = _requireUid();
    final packed = PayloadCodec.pack(payload.toJson());
    try {
      final row = await _db
          .from('properties')
          .insert({...columns, ...packed.toColumns(), 'owner_id': uid})
          .select()
          .single();
      return Listing.fromRow(Map<String, Object?>.from(row));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Rewrites a listing. owner_id and status are not editable through here:
  /// ownership is not a field, and status has its own control so that saving
  /// a correction never republishes something the owner had hidden.
  Future<Listing> update(String id, Map<String, Object?> columns, ListingPayload payload) async {
    final uid = _requireUid();
    final packed = PayloadCodec.pack(payload.toJson());
    final safe = Map<String, Object?>.from(columns)
      ..remove('owner_id')
      ..remove('status')
      ..remove('id');
    try {
      final row = await _db
          .from('properties')
          .update({...safe, ...packed.toColumns()})
          .eq('id', id)
          .eq('owner_id', uid)
          .select()
          .single();
      return Listing.fromRow(Map<String, Object?>.from(row));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> setStatus(String id, ListingStatus status) async {
    final uid = _requireUid();
    try {
      await _db.from('properties').update({'status': status.name}).eq('id', id).eq('owner_id', uid);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> delete(String id) async {
    final uid = _requireUid();
    try {
      await _db.from('properties').delete().eq('id', id).eq('owner_id', uid);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The owner-only exact pin (property_locations, migration 0010).
  Future<void> saveExactLocation(String propertyId, {required double lat, required double lng, String? address}) async {
    final uid = _requireUid();
    try {
      await _db.from('property_locations').upsert({
        'property_id': propertyId,
        'owner_id': uid,
        'lat': lat,
        'lng': lng,
        'address': address,
      }, onConflict: 'property_id');
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// The exact pin, for reopening an edit on the real point rather than the
  /// blurred one — reopening on the blurred point would walk the pin further
  /// from the building on every save. Null when there is none.
  Future<({double lat, double lng, String? address})?> exactLocation(String propertyId) async {
    try {
      final row = await _db
          .from('property_locations')
          .select('lat, lng, address')
          .eq('property_id', propertyId)
          .maybeSingle();
      if (row == null) return null;
      return (
        lat: (row['lat'] as num).toDouble(),
        lng: (row['lng'] as num).toDouble(),
        address: row['address'] as String?,
      );
    } on Object {
      return null;
    }
  }

  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
  static bool isListingId(String id) => _uuid.hasMatch(id);
}
