import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_failure.dart';
import '../../core/networking/api_client.dart';
import '../models/account_models.dart';
import '../models/search_constraints.dart';
import '../services/supabase_providers.dart';

final savedSearchesRepositoryProvider = Provider<SavedSearchesRepository>(
  (ref) => SavedSearchesRepository(ref.watch(supabaseClientProvider)),
);
final inquiriesRepositoryProvider = Provider<InquiriesRepository>(
  (ref) => InquiriesRepository(ref.watch(supabaseClientProvider)),
);
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(supabaseClientProvider)),
);
final accountRepositoryProvider = Provider<AccountRepository>((ref) => AccountRepository(ref.watch(apiClientProvider)));

String _uidOf(SupabaseClient db) {
  final id = db.auth.currentUser?.id;
  if (id == null) throw const AppFailure(FailureKind.unauthorized, detail: 'Not signed in');
  return id;
}

/// `public.saved_searches`: label + the website's constraints object. RLS
/// makes every row private to its owner for every operation.
class SavedSearchesRepository {
  SavedSearchesRepository(this._db);
  final SupabaseClient _db;

  Future<List<SavedSearch>> list() async {
    if (_db.auth.currentUser == null) return const [];
    try {
      final rows = await _db.from('saved_searches').select().order('created_at', ascending: false);
      return [for (final r in rows) SavedSearch.fromRow(Map<String, Object?>.from(r))];
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<SavedSearch> create(String label, SearchConstraints constraints) async {
    final uid = _uidOf(_db);
    try {
      final row = await _db
          .from('saved_searches')
          .insert({'user_id': uid, 'label': label.trim(), 'constraints': constraints.toJson()})
          .select()
          .single();
      return SavedSearch.fromRow(Map<String, Object?>.from(row));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> delete(String id) async {
    final uid = _uidOf(_db);
    try {
      await _db.from('saved_searches').delete().eq('id', id).eq('user_id', uid);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }
}

/// `public.inquiries`. Anyone may insert one against an active listing, as
/// its real owner (policy in 0008_hardening.sql); owners read what they
/// received and senders read what they sent.
class InquiriesRepository {
  InquiriesRepository(this._db);
  final SupabaseClient _db;

  /// Sends an inquiry. The row is inserted without being read back: a
  /// signed-out sender has no policy that lets them read it, and asking for
  /// it would turn a successful insert into a 401.
  ///
  /// sender_id is the session's user or null — never a value from the form —
  /// and the policy rejects anything else.
  Future<void> send({
    required String propertyId,
    required String ownerId,
    required String name,
    required String message,
    String? email,
    String? phone,
  }) async {
    try {
      await _db.from('inquiries').insert({
        'property_id': propertyId,
        'owner_id': ownerId,
        'sender_id': _db.auth.currentUser?.id,
        'name': name.trim(),
        'email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
        'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
        'message': message.trim(),
      });
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<List<Inquiry>> received() => _list('owner_id');
  Future<List<Inquiry>> sent() => _list('sender_id');

  Future<List<Inquiry>> _list(String column) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final rows = await _db
          .from('inquiries')
          .select('*, properties(title_en, title_ar)')
          .eq(column, uid)
          .order('created_at', ascending: false)
          .limit(100);
      return [for (final r in rows) Inquiry.fromRow(Map<String, Object?>.from(r))];
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }
}

/// `public.profiles`: self read and self write only.
class ProfileRepository {
  ProfileRepository(this._db);
  final SupabaseClient _db;

  Future<Profile?> mine() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
      return row == null ? null : Profile.fromRow(Map<String, Object?>.from(row));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> update({String? fullName, String? phone, String? locale}) async {
    final uid = _uidOf(_db);
    final changes = <String, Object?>{
      'full_name': ?fullName?.trim(),
      'phone': ?phone?.trim(),
      'locale': ?locale,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _db.from('profiles').update(changes).eq('id', uid);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }
}

class AccountDeletionUnavailable implements Exception {
  const AccountDeletionUnavailable();
}

/// Deleting an auth user needs the service-role key, so it can only happen
/// on the server: `DELETE /api/account` on the website, which verifies the
/// caller's own access token and deletes that account and nothing else.
///
/// If the deployed site predates that route, this throws
/// [AccountDeletionUnavailable] and the app falls back to the documented
/// email request (privacy@akarat.ai).
class AccountRepository {
  AccountRepository(this._api);
  final Dio _api;

  /// [appleAuthorizationCode]: Apple's confirmation, for an account that
  /// signs in with Apple; the server uses it to revoke Akarat.ai's access to
  /// the Apple ID, as Apple requires, before deleting.
  Future<void> deleteMyAccount({String? appleAuthorizationCode}) async {
    try {
      await _api.deleteUri<Object?>(
        Env.accountEndpoint,
        data: {'confirm': true, 'apple_authorization_code': ?appleAuthorizationCode},
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) throw const AccountDeletionUnavailable();
      throw AppFailure.from(e);
    }
  }
}
