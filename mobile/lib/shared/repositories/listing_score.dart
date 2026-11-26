import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/networking/api_client.dart';

/// Asks the website's server to work out a listing's quality score now
/// (POST /api/listings/score, lib/listing-score.js), so a new or edited
/// listing takes its place in the ranking within seconds. Fire and forget:
/// the nightly run scores anything this misses, and owners cannot set the
/// score themselves.
class ListingScoreApi {
  const ListingScoreApi(this._dio);
  final Dio _dio;

  Future<void> score(String id) async {
    try {
      await _dio.post<Object?>('/api/listings/score', data: {'id': id});
    } on Object {
      // Offline or the server is busy: the nightly run scores it.
    }
  }
}

final listingScoreProvider = Provider<ListingScoreApi>((ref) => ListingScoreApi(ref.watch(apiClientProvider)));
