import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../shared/services/supabase_providers.dart';
import '../config/env.dart';

/// HTTP client for the website's own API routes on Vercel.
///
/// Every privileged credential — the service-role key, search-provider keys,
/// the cron secret — stays in Vercel's environment. The app only ever sends
/// the signed-in user's Supabase access token, which the route verifies with
/// Supabase before trusting it. Browser cookies do not exist here, so the
/// token travels as a standard bearer header.
final apiClientProvider = Provider<Dio>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.siteUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: {'X-Akarat-Client': 'mobile'},
    ),
  );
  dio.interceptors.add(_AuthInterceptor(client));
  ref.onDispose(dio.close);
  return dio;
});

/// Only the website's own API, over HTTPS, ever sees the user's token, even
/// if a request is one day made to a full URL on another host.
bool carriesToken(Uri uri) => uri.scheme == 'https' && uri.host == Uri.parse(Env.siteUrl).host;

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);
  final SupabaseClient _client;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // currentSession is refreshed by the Supabase client on its own timer;
    // an expired one is simply not sent, and the route treats the call as
    // anonymous rather than failing it.
    final session = _client.auth.currentSession;
    if (carriesToken(options.uri) && session != null && !session.isExpired) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }
}
