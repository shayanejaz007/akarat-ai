import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../services/supabase_providers.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(supabaseClientProvider)),
);

/// Why someone reports a listing.
enum ReportReason {
  scam('scam'),
  wrongDetails('wrong_details'),
  unavailable('unavailable'),
  offensive('offensive'),
  other('other');

  const ReportReason(this.stored);

  /// The value public.listing_reports.reason accepts.
  final String stored;
}

/// The reports table is not there yet (migration 0015 has not run).
class ReportsUnavailable implements Exception {
  const ReportsUnavailable();
}

/// `public.listing_reports` (migration 0015): reports go in, and nothing
/// comes back out through the API. The team reads them in the dashboard.
class ReportsRepository {
  ReportsRepository(this._db);
  final SupabaseClient _db;

  /// Files a report of [propertyId] as the signed-in reader. Reporting the
  /// same listing twice counts as done. Throws [ReportsUnavailable] until
  /// migration 0015 runs, so the caller can send it by email instead.
  Future<void> reportListing(String propertyId, ReportReason reason, {String? details}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw const AppFailure(FailureKind.unauthorized, detail: 'Not signed in');
    final note = details?.trim() ?? '';
    try {
      await _db.from('listing_reports').insert({
        'property_id': propertyId,
        'reporter_id': uid,
        'reason': reason.stored,
        if (note.isNotEmpty) 'details': note.length > 1000 ? note.substring(0, 1000) : note,
      });
    } on PostgrestException catch (e) {
      // 23505: this person already reported it.
      if (e.code == '23505') return;
      // PGRST205 / 42P01: no such table yet. 42501: no grant yet.
      if (e.code == 'PGRST205' || e.code == '42P01' || e.code == '42501') throw const ReportsUnavailable();
      throw AppFailure.from(e);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }
}
