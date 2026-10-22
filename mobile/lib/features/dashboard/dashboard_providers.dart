import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/listing.dart';
import '../../shared/repositories/listings_repository.dart';
import '../../shared/services/refresh.dart';
import '../../shared/services/supabase_providers.dart';

/// Every listing the signed-in user owns, any status — the same rows the
/// website's dashboard lists.
final myListingsProvider = FutureProvider.autoDispose<List<Listing>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  ref.watch(refreshTickProvider);
  return ref.watch(listingsRepositoryProvider).mine();
});
