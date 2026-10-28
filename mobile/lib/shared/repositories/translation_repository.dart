import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/networking/api_client.dart';

final translationRepositoryProvider = Provider<TranslationRepository>(
  (ref) => TranslationRepository(ref.watch(apiClientProvider)),
);

/// English ⇄ Arabic for a listing's title and description, through the
/// website's `POST /api/translate` (app/api/translate/route.ts), which holds
/// the model key. Same route the website's form uses.
///
/// Never throws: signed out, an older deployment without the route, no key
/// configured, or a slow network all return null, and the form carries on
/// exactly as it did before translation existed.
class TranslationRepository {
  TranslationRepository(this._api);
  final Dio _api;

  Future<({String title, String description})?> translate({
    required String from,
    String title = '',
    String description = '',
  }) async {
    if (title.trim().isEmpty && description.trim().isEmpty) return null;
    try {
      final res = await _api.postUri<Map<String, dynamic>>(
        Env.translateEndpoint,
        data: {'from': from, 'title': title, 'description': description},
        // A long description takes the model a few seconds.
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );
      final body = res.data;
      if (body == null) return null;
      return (title: '${body['title'] ?? ''}'.trim(), description: '${body['description'] ?? ''}'.trim());
    } on Object {
      return null;
    }
  }
}
