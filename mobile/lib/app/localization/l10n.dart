import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_failure.dart';
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
}
