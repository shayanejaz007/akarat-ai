import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/account_models.dart';
import '../../shared/repositories/account_repositories.dart';
import '../../shared/services/supabase_providers.dart';

/// Inquiries about the signed-in user's listings — what the website's
/// dashboard shows under "Inquiries".
final receivedInquiriesProvider = FutureProvider.autoDispose<List<Inquiry>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(inquiriesRepositoryProvider).received();
});

/// Inquiries the signed-in user sent to other owners.
final sentInquiriesProvider = FutureProvider.autoDispose<List<Inquiry>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(inquiriesRepositoryProvider).sent();
});
