import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'preferences.dart';
import 'supabase_providers.dart';

final activityProvider = Provider<Activity>(
  (ref) => Activity(ref.watch(supabaseClientProvider), ref.watch(preferencesProvider)),
);

/// What the admin panel (akarat.ai/admin) counts from the app: that it is
/// open, and which listings are opened. Same two database functions the
/// website calls (supabase/migrations/0018_admin_analytics.sql), keyed by a
/// random per-install id. A signed-in session is tied to its account by the
/// database itself, from the request's own token.
///
/// Never throws and never waits on anything the reader sees: a database
/// without 0018, or no connection, just means the visit is not counted.
class Activity {
  Activity(this._db, this._prefs);
  final SupabaseClient _db;
  final Preferences _prefs;

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  /// About once a minute while the app is in front (AkaratApp).
  Future<void> heartbeat() async {
    try {
      await _db.rpc<void>('heartbeat', params: {'p_session': _prefs.sessionId, 'p_platform': _platform});
    } on Object {
      // not counted
    }
  }

  /// A listing's page was opened. Repeat opens within 30 minutes are one view
  /// (the database decides).
  Future<void> recordView(String propertyId) async {
    try {
      await _db.rpc<void>(
        'record_view',
        params: {'p_property': propertyId, 'p_session': _prefs.sessionId, 'p_platform': _platform},
      );
    } on Object {
      // not counted
    }
  }
}
