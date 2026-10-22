import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../services/supabase_providers.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepository(ref.watch(supabaseClientProvider)),
);

/// Saved properties, per account, in `public.favorites`.
///
/// That table is added by supabase/migrations/0014_favorites.sql, an additive
/// migration that has to be reviewed and applied to production by hand. Until
/// it is, [isAvailable] reports false and the app keeps favourites on the
/// device instead of failing — see FavoritesController.
///
/// The website currently keeps saved listings in page memory only. Once 0014
/// is live, it can read the same table and the two will agree.
class FavoritesRepository {
  FavoritesRepository(this._db);
  final SupabaseClient _db;

  /// True when the table exists and this session may read it.
  Future<bool> isAvailable() async {
    try {
      await _db.from('favorites').select('property_id').limit(1);
      return true;
    } on PostgrestException catch (e) {
      // PGRST205: table not in the schema cache. 42501: no grant. Either way
      // the migration has not been applied.
      if (e.code == 'PGRST205' || e.code == '42P01' || e.code == '42501') return false;
      throw AppFailure.from(e);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Property ids, most recently saved first.
  Future<List<String>> list() async {
    try {
      final rows = await _db.from('favorites').select('property_id').order('created_at', ascending: false);
      return [for (final r in rows) r['property_id'] as String];
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// user_id is the session's, never the caller's; RLS checks it too.
  Future<void> add(String propertyId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AppFailure(FailureKind.unauthorized);
    try {
      await _db
          .from('favorites')
          .upsert(
            {'user_id': uid, 'property_id': propertyId},
            onConflict: 'user_id,property_id',
            ignoreDuplicates: true,
          );
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> addAll(Iterable<String> propertyIds) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AppFailure(FailureKind.unauthorized);
    final rows = [
      for (final id in propertyIds) {'user_id': uid, 'property_id': id},
    ];
    if (rows.isEmpty) return;
    try {
      await _db.from('favorites').upsert(rows, onConflict: 'user_id,property_id', ignoreDuplicates: true);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> remove(String propertyId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AppFailure(FailureKind.unauthorized);
    try {
      await _db.from('favorites').delete().eq('user_id', uid).eq('property_id', propertyId);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }
}
