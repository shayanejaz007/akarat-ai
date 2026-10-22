import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferences.dart';

/// Advertisers this reader has hidden, by account id. Kept on the device.
///
/// The listings and search repositories watch it, so hiding someone refetches
/// every list at once without their listings, and showing them again brings
/// them back the same way. Only well-formed ids are kept, because they go
/// into a database filter.
final hiddenOwnersProvider = NotifierProvider<HiddenOwners, Set<String>>(HiddenOwners.new);

class HiddenOwners extends Notifier<Set<String>> {
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  @override
  Set<String> build() => {...ref.read(preferencesProvider).hiddenOwners.where(_uuid.hasMatch)};

  Future<void> hide(String ownerId) async {
    if (!_uuid.hasMatch(ownerId) || state.contains(ownerId)) return;
    state = {...state, ownerId};
    await ref.read(preferencesProvider).setHiddenOwners(state.toList()..sort());
  }

  Future<void> showAll() async {
    state = const {};
    await ref.read(preferencesProvider).setHiddenOwners(const []);
  }
}
