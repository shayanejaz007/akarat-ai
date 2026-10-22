import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/networking/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/listing.dart';
import '../../../shared/models/search_constraints.dart';
import '../../../shared/services/supabase_providers.dart';
import '../domain/ranker.dart';
import '../domain/search_item.dart';

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(apiClientProvider), ref.watch(supabaseClientProvider)),
);

class RankedResult {
  const RankedResult(this.item, this.score);
  final SearchItem item;
  final int score;
}

class SearchCoverage {
  const SearchCoverage({this.providersQueried = 0, this.providersTotal = 0, this.unavailable = const []});

  final int providersQueried;
  final int providersTotal;

  /// What was NOT searched, in the route's own words ("X: not configured").
  final List<String> unavailable;

  static SearchCoverage fromJson(Object? json) {
    if (json is! Map) return const SearchCoverage();
    final u = json['unavailable'];
    return SearchCoverage(
      providersQueried: (json['providersQueried'] as num?)?.toInt() ?? 0,
      providersTotal: (json['providersTotal'] as num?)?.toInt() ?? 0,
      unavailable: u is List ? u.whereType<String>().toList() : const [],
    );
  }
}

class SearchOutcome {
  const SearchOutcome({
    required this.results,
    required this.internalCount,
    required this.externalCount,
    required this.coverage,
    required this.servedDirect,
  });

  /// Every result, Akarat.ai and external, ranked by one arithmetic.
  final List<RankedResult> results;
  final int internalCount;
  final int externalCount;
  final SearchCoverage coverage;

  /// True when the Vercel route did not answer and Akarat.ai's own listings
  /// were read straight from the database instead. Shown to the reader.
  final bool servedDirect;

  List<RankedResult> get internal => results.where((r) => !r.item.isExternal).toList();
  List<RankedResult> get external => results.where((r) => r.item.isExternal).toList();
}

/// The search pipeline, as the website runs it:
///
///   parse (on device, QueryParser) → POST /api/ai/search on Vercel
///     → Akarat.ai listings through RLS + licensed partner feeds server-side
///   ∥ the crawler's external index (external_properties_grouped), read-only
///   → the same filters → one deterministic ranking (Ranker)
///
/// No provider key, LLM key or crawler credential is involved on the device.
class SearchRepository {
  SearchRepository(this._api, this._db);
  final Dio _api;
  final SupabaseClient _db;

  Future<SearchOutcome> search(SearchConstraints c, {CancelToken? cancelToken, DateTime? now}) async {
    // Both start at once. Awaited one by one rather than with `.wait`, which
    // would wrap a failure in ParallelWaitError and turn "rate limited" into
    // an unexplained error. The index read never throws (see _externalIndex),
    // so nothing is left unhandled if the internal search fails first.
    final indexFuture = c.internalOnly ? Future.value(const <SearchItem>[]) : _externalIndex(c, now: now);
    final internal = await _internal(c, cancelToken);
    final index = await indexFuture;

    final at = now ?? DateTime.now();
    final pool = <SearchItem>[
      ..._filterInternal(internal.rows, c).map((l) => SearchItem.fromListing(l, now: at)),
      ...internal.partner,
      ...index,
    ];
    final ranked = [for (final it in pool) RankedResult(it, Ranker.score(it, c))];
    // Stable: equal scores keep retrieval order, as Array.prototype.sort does.
    final indexed = ranked.asMap().entries.toList()
      ..sort((a, b) {
        final byScore = b.value.score - a.value.score;
        return byScore != 0 ? byScore : a.key - b.key;
      });

    return SearchOutcome(
      results: [for (final e in indexed) e.value],
      internalCount: pool.where((i) => !i.isExternal).length,
      externalCount: pool.where((i) => i.isExternal).length,
      coverage: internal.coverage,
      servedDirect: internal.servedDirect,
    );
  }

  Future<_InternalResult> _internal(SearchConstraints c, CancelToken? cancelToken) async {
    try {
      final res = await _api.postUri<Object?>(
        Env.searchEndpoint,
        data: {'constraints': c.toJson()},
        cancelToken: cancelToken,
      );
      final body = res.data;
      if (body is! Map) throw const AppFailure(FailureKind.unknown, detail: 'search: unexpected body');
      final rows = body['internal'];
      final external = body['external'];
      return _InternalResult(
        rows: rows is List
            ? rows.whereType<Map<String, dynamic>>().map((r) => Listing.fromRow(Map<String, Object?>.from(r))).toList()
            : const [],
        partner: external is List
            ? external.whereType<Map<String, dynamic>>().map(_partnerItem).nonNulls.toList()
            : const [],
        coverage: SearchCoverage.fromJson(body['coverage']),
        servedDirect: false,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      final status = e.response?.statusCode;
      // The limiter is there to be respected, not routed around.
      if (status == 429) throw AppFailure(FailureKind.rateLimited, status: status);
      if (status == 400) {
        throw AppFailure(FailureKind.validation, status: status, detail: 'search rejected constraints');
      }
      // Network trouble or a 5xx: read Akarat.ai's own listings directly, the
      // way the website's own search does, and say so in the results.
      return _direct(c);
    }
  }

  /// The route's internal query, run against Postgres with the same RLS.
  Future<_InternalResult> _direct(SearchConstraints c) async {
    try {
      var q = _db.from('properties').select().eq('status', 'active');
      if (c.deal != null) q = q.eq('deal', c.deal!);
      if (c.city != null) q = q.eq('city_id', c.city!);
      if (c.type != null) q = q.eq('property_type', c.type!);
      if (c.budgetMax case final max? when max != 0) q = q.lte('price_jod', _int32((max * 1.15).round()));
      if (c.budgetMin case final min? when min != 0) q = q.gte('price_jod', _int32(min));
      if (c.beds case final b?) q = q.gte('bedrooms', b - 1);
      final rows = await q.limit(60);
      return _InternalResult(
        rows: [for (final r in rows) Listing.fromRow(Map<String, Object?>.from(r))],
        partner: const [],
        coverage: const SearchCoverage(),
        servedDirect: true,
      );
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  static int _int32(int v) => v > 2147483647 ? 2147483647 : v;

  /// The website's searchInternal filter. A sold or rented listing stays on
  /// the marketplace but is never offered as a match.
  static List<Listing> _filterInternal(List<Listing> rows, SearchConstraints c) => rows.where((p) {
    if (p.isClosed) return false;
    if (c.deal != null && p.deal.name != c.deal) return false;
    if (c.type != null && p.propertyType != c.type) return false;
    if (c.city != null && p.cityId != c.city) return false;
    if (c.budgetMax case final max? when max != 0) {
      if (p.priceJod > max * 1.15) return false;
    }
    if (c.budgetMin case final min? when min != 0) {
      if (p.priceJod < min) return false;
    }
    if (c.beds case final b?) {
      if ((p.bedrooms ?? 0) < b - 1) return false;
    }
    if (c.baths case final b?) {
      if ((p.bathrooms ?? 0) < b - 1) return false;
    }
    // No area recorded: kept and ranked down, not dropped.
    if (c.areaMin case final a?) {
      if (p.areaSqm != null && p.areaSqm! < a * 0.85) return false;
    }
    return true;
  }).toList();

  /// The crawler's index, one row per distinct property. Errors are quiet,
  /// as on the website: an unreachable index means "no external rows", and
  /// the portal links below the results still work.
  Future<List<SearchItem>> _externalIndex(SearchConstraints c, {DateTime? now}) async {
    try {
      var q = _db.from('external_properties_grouped').select();
      if (c.deal != null) q = q.eq('transaction_type', c.deal!);
      if (c.city != null) q = q.eq('city_id', c.city!);
      if (c.hood != null) q = q.eq('neighborhood_id', c.hood!);
      if (c.budgetMax case final max? when max != 0) q = q.lte('price_low', _int32((max * 1.15).round()));
      if (c.budgetMin case final min? when min != 0) q = q.gte('price_low', _int32(min));
      if (c.beds case final b?) q = q.gte('bedrooms', b - 1 < 0 ? 0 : b - 1);
      if (c.baths case final b?) q = q.gte('bathrooms', b - 1 < 0 ? 0 : b - 1);
      final rows = await q.order('last_seen_at', ascending: false).limit(30);
      final at = now ?? DateTime.now();
      return [for (final r in rows) _indexItem(Map<String, Object?>.from(r), at)];
    } on Object {
      return const [];
    }
  }

  static SearchItem _indexItem(Map<String, Object?> r, DateTime now) {
    final raw = r['listings'];
    final links = <ExternalSourceLink>[
      if (raw is List)
        for (final l in raw.whereType<Map<String, dynamic>>())
          if (l['url'] is String)
            ExternalSourceLink(
              sourceId: (l['source_id'] as String?) ?? '',
              url: l['url'] as String,
              price: (l['price'] as num?)?.toInt(),
              lastCheckedAt: DateTime.tryParse((l['last_checked_at'] as String?) ?? ''),
            ),
    ];
    DateTime? freshest;
    for (final l in links) {
      final t = l.lastCheckedAt;
      if (t != null && (freshest == null || t.isAfter(freshest))) freshest = t;
    }
    final sources = (r['sources'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final title = (r['title'] as String?) ?? '';
    return SearchItem(
      id: 'x-${r['group_key']}',
      titleEn: title,
      titleAr: title,
      source: sources.length > 1 ? '${sources.length} sources' : (sources.isNotEmpty ? sources.first : 'external'),
      kind: 'known_marketplace',
      sources: sources,
      sourceLinks: links,
      url: links.isNotEmpty ? links.first.url : null,
      deal: r['transaction_type'] as String?,
      type: (r['property_type'] as String?)?.toLowerCase(),
      city: r['city_id'] as String?,
      hood: r['neighborhood_id'] as String?,
      price: (r['price_low'] as num?)?.toInt(),
      priceHigh: (r['price_high'] as num?)?.toInt(),
      beds: (r['bedrooms'] as num?)?.toInt(),
      baths: (r['bathrooms'] as num?)?.toInt(),
      area: (r['area_sqm'] as num?)?.toInt(),
      imageUrl: r['image_url'] as String?,
      checked: freshest == null ? null : Fmt.daysSince(freshest, now: now),
    );
  }

  /// A licensed partner feed row, normalised server-side by the route.
  static SearchItem? _partnerItem(Map<String, dynamic> r) {
    final url = r['sourceUrl'];
    if (url is! String || url.isEmpty) return null;
    final title = (r['title'] as String?) ?? '';
    final checkedAt = DateTime.tryParse((r['lastCheckedAt'] as String?) ?? '');
    return SearchItem(
      id: 'p-${r['externalId'] ?? url}',
      titleEn: title,
      titleAr: title,
      source: (r['sourceName'] as String?) ?? 'partner',
      kind: 'licensed_feed',
      url: url,
      deal: r['transactionType'] as String?,
      type: (r['propertyType'] as String?)?.toLowerCase(),
      price: (r['price'] as num?)?.toInt(),
      beds: (r['bedrooms'] as num?)?.toInt(),
      baths: (r['bathrooms'] as num?)?.toInt(),
      area: (r['areaSqm'] as num?)?.toInt(),
      imageUrl: r['imageUrl'] as String?,
      checked: checkedAt == null ? null : Fmt.daysSince(checkedAt),
    );
  }
}

class _InternalResult {
  const _InternalResult({
    required this.rows,
    required this.partner,
    required this.coverage,
    required this.servedDirect,
  });
  final List<Listing> rows;
  final List<SearchItem> partner;
  final SearchCoverage coverage;
  final bool servedDirect;
}
