import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Increments when cached marketplace data should be considered stale: the
/// app returning from the background, or a listing being created, edited,
/// re-statused or deleted from this device. List providers watch it and
/// refetch, so nobody keeps seeing a listing that changed on the website.
final refreshTickProvider = NotifierProvider<RefreshTick, int>(RefreshTick.new);

class RefreshTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
