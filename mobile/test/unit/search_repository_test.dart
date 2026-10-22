import 'dart:convert';
import 'dart:typed_data';

import 'package:akarat/core/errors/app_failure.dart';
import 'package:akarat/core/utils/payload_codec.dart';
import 'package:akarat/features/ai_search/data/search_repository.dart';
import 'package:akarat/shared/models/search_constraints.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthClientOptions, SupabaseClient;

/// Answers every request with [status] and [body], and records what was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  RequestOptions? last;
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    lastBody = options.data;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _row(
  String id, {
  String status = 'active',
  int price = 140000,
  int? beds = 3,
  String deal = 'sale',
}) => {
  'id': id,
  'owner_id': '22222222-2222-4222-8222-222222222222',
  'status': status,
  'deal': deal,
  'property_type': 'apartment',
  'city_id': 'amman',
  'neighborhood_id': 'abdoun',
  'price_jod': price,
  'bedrooms': beds,
  'title_en': 'Row $id',
  'payload_gz': PayloadCodec.pack({'amenities': <String>[]}).payloadGz,
  'created_at': DateTime.now().toUtc().toIso8601String(),
};

SearchRepository _repo(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  final db = SupabaseClient(
    'https://supabase.invalid',
    'k',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return SearchRepository(dio, db);
}

void main() {
  // internalOnly keeps these tests off the external index, which would need
  // a database.
  const c = SearchConstraints(
    deal: 'sale',
    city: 'amman',
    hood: 'abdoun',
    beds: 3,
    budgetMax: 150000,
    internalOnly: true,
  );

  test('posts the website-shaped constraints and ranks what comes back', () async {
    final adapter = _Adapter(200, {
      'internal': [
        _row('a', price: 260000), // over budget × 1.15: filtered out, as on the website
        _row('b', price: 145000),
        _row('c', status: 'sold'), // closed: never offered as a match
        _row('d', price: 120000, beds: 4),
      ],
      'external': <Object>[],
      'coverage': {
        'providersQueried': 0,
        'providersTotal': 1,
        'unavailable': ['Licensed partner feed: not configured'],
      },
    });
    final out = await _repo(adapter).search(c);
    expect(adapter.last!.uri.path, '/api/ai/search');
    expect((adapter.lastBody! as Map)['constraints'], c.toJson());
    // Equal scores keep retrieval order, as Array.prototype.sort does.
    expect(out.results.map((r) => r.item.id), ['b', 'd']);
    expect(out.results.first.score, out.results.last.score);
    expect(out.coverage.unavailable, ['Licensed partner feed: not configured']);
    expect(out.servedDirect, isFalse);
  });

  test('a 429 is reported as rate limiting, not as an empty result or a generic error', () async {
    final adapter = _Adapter(429, {'error': 'Too many searches. Try again shortly.'});
    await expectLater(
      _repo(adapter).search(c),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.rateLimited)),
    );
  });

  test('partner-feed rows are kept apart as external results', () async {
    final adapter = _Adapter(200, {
      'internal': <Object>[],
      'external': [
        {
          'externalId': 'p1',
          'sourceName': 'Licensed partner feed',
          'sourceUrl': 'https://partner.invalid/p1',
          'title': 'Partner flat',
          'transactionType': 'sale',
          'price': 149000,
          'bedrooms': 3,
          'lastCheckedAt': DateTime.now().toUtc().toIso8601String(),
        },
        {'title': 'No URL, dropped'},
      ],
      'coverage': {'providersQueried': 1, 'providersTotal': 1, 'unavailable': <String>[]},
    });
    final out = await _repo(adapter).search(c);
    expect(out.external.single.item.url, 'https://partner.invalid/p1');
    expect(out.external.single.item.kind, 'licensed_feed');
    expect(out.internal, isEmpty);
  });
}
