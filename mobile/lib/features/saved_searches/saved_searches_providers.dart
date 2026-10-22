import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/account_models.dart';
import '../../shared/repositories/account_repositories.dart';
import '../../shared/services/supabase_providers.dart';

/// The signed-in user's saved searches, newest first. Empty when signed out.
final savedSearchesProvider = FutureProvider.autoDispose<List<SavedSearch>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return ref.watch(savedSearchesRepositoryProvider).list();
});
