import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_failure.dart';
import '../../shared/models/daily_models.dart' show DailyRefusal;
import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// 'ar' or 'en' — what the data layer's bilingual helpers take.
  String get lang => Localizations.localeOf(this).languageCode == 'ar' ? 'ar' : 'en';
  bool get isArabic => lang == 'ar';

  /// A sentence for any error, never the raw database or HTTP text.
  String failureMessage(Object error) {
    final l = l10n;
    if (error is DailyRefusal) return _dailyRefusal(error);
    final f = AppFailure.from(error);
    return switch (f.kind) {
      FailureKind.network => l.errorNetwork,
      FailureKind.timeout => l.errorTimeout,
      FailureKind.rateLimited => l.errorRateLimited,
      FailureKind.unauthorized => l.errorSessionExpired,
      FailureKind.forbidden => l.errorPermission,
      FailureKind.notFound => l.errorNotFound,
      FailureKind.unknownArea => l.errorUnknownArea,
      FailureKind.storageMissing => l.errorStorageMissing,
      FailureKind.schemaMissing || FailureKind.validation || FailureKind.unknown => l.errorGeneric,
    };
  }

  /// The database's daily-rental refusals (0019_daily_rentals.sql), worded.
  String _dailyRefusal(DailyRefusal e) {
    final l = l10n;
    final n = e.n ?? 0;
    return switch (e.key) {
      'daily_sign_in' => l.dailyErrSignIn,
      'daily_not_bookable' => l.dailyErrNotBookable,
      'daily_own_listing' => l.dailyErrOwn,
      'daily_bad_dates' => l.dailyErrBadDates,
      'daily_past_dates' => l.dailyErrPast,
      'daily_too_far' => l.dailyErrTooFar,
      'daily_min_nights' => l.dailyErrMinNights(n),
      'daily_max_nights' => l.dailyErrMaxNights(n),
      'daily_max_guests' => l.dailyErrMaxGuests(n),
      'daily_bad_guests' => l.dailyErrBadGuests,
      'daily_unavailable' => l.dailyErrUnavailable,
      'daily_open_request' => l.dailyErrOpenRequest,
      'daily_too_many' => l.dailyErrTooMany,
      'daily_phone_needed' => l.dailyErrPhoneNeeded,
      'daily_request_closed' => l.dailyErrClosed,
      'daily_request_missing' => l.dailyErrMissing,
      'daily_not_yours' => l.dailyErrNotYours,
      _ => l.errorGeneric,
    };
  }
}
