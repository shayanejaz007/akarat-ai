import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../models/daily_models.dart';
import '../models/listing.dart';
import '../services/supabase_providers.dart';

final dailyRepositoryProvider = Provider<DailyRepository>((ref) => DailyRepository(ref.watch(supabaseClientProvider)));

/// Daily rentals (supabase/migrations/0019_daily_rentals.sql), read and
/// written with the publishable key, the same way the website does.
///
/// Every rule lives in the database: a daily listing is public only once an
/// admin approves it; a request is checked against the minimum stay, the
/// guest limit and the calendar; the owner's phone is written onto a request
/// only when they approve it; and two confirmed stays can never overlap.
/// Nothing here can widen any of that.
class DailyRepository {
  DailyRepository(this._db);
  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  String _requireUid() {
    final id = _uid;
    if (id == null) throw const AppFailure(FailureKind.unauthorized, detail: 'Not signed in');
    return id;
  }

  /// A refusal the reader can act on, or the usual failure.
  static Object _fail(Object e) {
    if (e is PostgrestException && e.message.startsWith('daily_')) {
      final key = RegExp(r'^daily_[a-z_]+').firstMatch(e.message)![0]!;
      return DailyRefusal(key, n: int.tryParse('${e.details ?? ''}'));
    }
    return AppFailure.from(e);
  }

  /// The database has no daily rentals yet: 0019 has not been run. Lists
  /// read as empty then, rather than as an error on every screen.
  static bool _notMigrated(Object e) =>
      e is PostgrestException &&
      const {'PGRST202', 'PGRST205', '42883', '42P01', '22P02'}.contains(e.code) &&
      RegExp('daily|booking_requests|deal_type').hasMatch('${e.message} ${e.details ?? ''} ${e.hint ?? ''}');

  /// Approved daily rentals, newest first. With both dates, only those free
  /// for every night of the stay and taking that many nights; with [guests],
  /// only those that sleep that many.
  Future<List<Listing>> search({
    DateTime? checkIn,
    DateTime? checkOut,
    int? guests,
    String? cityId,
    int limit = 60,
  }) async {
    final dated = checkIn != null && checkOut != null;
    try {
      var q = _db.rpc<List<dynamic>>(
        'search_daily_rentals',
        params: {
          'p_check_in': dated ? isoDay(checkIn) : null,
          'p_check_out': dated ? isoDay(checkOut) : null,
          'p_guests': guests,
        },
      );
      if (cityId != null) q = q.eq('city_id', cityId);
      final rows = await q.order('created_at', ascending: false).limit(limit);
      final out = <Listing>[];
      for (final r in rows) {
        try {
          out.add(Listing.fromRow(Map<String, Object?>.from(r as Map)));
        } on Object catch (e) {
          if (kDebugMode) debugPrint('Skipped unreadable daily listing: $e');
        }
      }
      return out;
    } on Object catch (e) {
      if (_notMigrated(e)) return const [];
      throw _fail(e);
    }
  }

  /// Nights a calendar should grey out between [from] and [to]: closed by the
  /// owner or inside a confirmed stay. Says nothing about whose.
  Future<Set<DateTime>> unavailable(String propertyId, DateTime from, DateTime to) async {
    try {
      final days = await _db.rpc<List<dynamic>>(
        'daily_unavailable_days',
        params: {'p_property': propertyId, 'p_from': isoDay(from), 'p_to': isoDay(to)},
      );
      return {for (final d in days) ?parseDay(d)};
    } on Object catch (e) {
      throw _fail(e);
    }
  }

  /// Asks the owner for these dates. The owner, the price and the total are
  /// filled in by the database from the listing, never taken from here.
  Future<BookingRequest> request({
    required String propertyId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
    String? message,
    String? name,
  }) async {
    final uid = _requireUid();
    final meta = _db.auth.currentUser?.userMetadata;
    try {
      final row = await _db
          .from('booking_requests')
          .insert({
            'property_id': propertyId,
            'renter_id': uid,
            'renter_name': (name?.trim().isNotEmpty ?? false) ? name!.trim() : (meta?['full_name'] as String? ?? ''),
            'check_in': isoDay(checkIn),
            'check_out': isoDay(checkOut),
            'guests': guests,
            'message': (message?.trim().isEmpty ?? true) ? null : message!.trim(),
          })
          .select()
          .single();
      return BookingRequest.fromRow(Map<String, Object?>.from(row));
    } on Object catch (e) {
      throw _fail(e);
    }
  }

  static const _columns =
      'id,property_id,owner_id,renter_id,renter_name,check_in,check_out,nights,guests,message,'
      'nightly_price,total_price,status,owner_phone,response_note,closed_reason,cancelled_by,responded_at,created_at';

  List<BookingRequest> _requests(List<Map<String, dynamic>> rows) => [
    for (final r in rows) BookingRequest.fromRow(Map<String, Object?>.from(r)),
  ];

  /// The signed-in person's own requests, newest first.
  Future<List<BookingRequest>> mine() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      return _requests(
        await _db
            .from('booking_requests')
            .select('$_columns,properties(id,title_en,title_ar,payload_gz)')
            .eq('renter_id', uid)
            .order('created_at', ascending: false)
            .limit(100),
      );
    } on Object catch (e) {
      if (_notMigrated(e)) return const [];
      throw _fail(e);
    }
  }

  /// Requests for the signed-in owner's listings, newest first.
  Future<List<BookingRequest>> incoming() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      return _requests(
        await _db
            .from('booking_requests')
            .select('$_columns,properties(id,title_en,title_ar,payload_gz)')
            .eq('owner_id', uid)
            .order('created_at', ascending: false)
            .limit(200),
      );
    } on Object catch (e) {
      if (_notMigrated(e)) return const [];
      throw _fail(e);
    }
  }

  Future<BookingRequest> respond(String id, BookingAction action, {String? phone, String? note}) async {
    _requireUid();
    try {
      final out = await _db.rpc<Object?>(
        'booking_respond',
        params: {'p_request': id, 'p_action': action.name, 'p_phone': phone, 'p_note': note},
      );
      // One row comes back as an object; take the first if it ever arrives
      // as a list, rather than calling a change that worked a failure.
      final row = out is List ? out.first : out;
      return BookingRequest.fromRow(Map<String, Object?>.from(row! as Map));
    } on Object catch (e) {
      throw _fail(e);
    }
  }

  /// The number an owner last shared, else the one on their profile or
  /// account, to fill the approval box.
  Future<String> lastSharedPhone() async {
    final uid = _uid;
    if (uid == null) return '';
    try {
      final shared = await _db
          .from('booking_requests')
          .select('owner_phone')
          .eq('owner_id', uid)
          .not('owner_phone', 'is', null)
          .order('responded_at', ascending: false)
          .limit(1);
      if (shared.isNotEmpty && shared.first['owner_phone'] is String) return shared.first['owner_phone'] as String;
      final profile = await _db.from('profiles').select('phone').eq('id', uid).maybeSingle();
      final phone = profile?['phone'] as String?;
      if (phone != null && phone.trim().isNotEmpty) return phone;
    } on Object {
      // Nothing to suggest; the owner types it.
    }
    final own = _db.auth.currentUser?.phone ?? '';
    return own.isEmpty ? '' : '+${own.replaceFirst('+', '')}';
  }

  /// Nights the owner has closed on one listing.
  Future<Set<DateTime>> blockedDays(String propertyId) async {
    try {
      final rows = await _db.from('daily_blocked_days').select('day').eq('property_id', propertyId);
      return {for (final r in rows) ?parseDay(r['day'])};
    } on Object catch (e) {
      throw _fail(e);
    }
  }

  Future<void> setBlocked(String propertyId, DateTime day, {required bool blocked}) async {
    _requireUid();
    try {
      if (blocked) {
        await _db
            .from('daily_blocked_days')
            .upsert(
              {'property_id': propertyId, 'day': isoDay(day)},
              onConflict: 'property_id,day',
              ignoreDuplicates: true,
            );
      } else {
        await _db.from('daily_blocked_days').delete().eq('property_id', propertyId).eq('day', isoDay(day));
      }
    } on Object catch (e) {
      throw _fail(e);
    }
  }

  Future<List<AppNotification>> notifications() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _db
          .from('notifications')
          .select('id,kind,property_id,booking_id,data,read_at,created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(60);
      return [for (final r in rows) AppNotification.fromRow(Map<String, Object?>.from(r))];
    } on Object catch (e) {
      // Not migrated yet reads as "nothing new", not as an error on every tab.
      final f = AppFailure.from(e);
      if (f.kind == FailureKind.schemaMissing) return const [];
      throw f;
    }
  }

  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid)
          .isFilter('read_at', null);
    } on Object {
      // Stays unread; nothing else depends on it.
    }
  }

  /// One event whenever this account gets a notification or one of its
  /// requests changes, as it happens. Cancel the subscription to stop.
  Stream<void> changes(String userId) {
    late final RealtimeChannel channel;
    late final StreamController<void> out;
    out = StreamController<void>(
      onCancel: () async {
        await _db.removeChannel(channel);
        await out.close();
      },
    );
    void ping(PostgresChangePayload _) {
      if (!out.isClosed) out.add(null);
    }

    PostgresChangeFilter by(String column) =>
        PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: userId);
    channel = _db
        .channel('account:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: by('user_id'),
          callback: ping,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_requests',
          filter: by('owner_id'),
          callback: ping,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'booking_requests',
          filter: by('renter_id'),
          callback: ping,
        )
        .subscribe();
    return out.stream;
  }
}
