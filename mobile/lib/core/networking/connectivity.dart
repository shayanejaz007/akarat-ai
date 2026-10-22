import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device has any network interface up. A hint for the offline
/// banner, not a guarantee: a connected Wi-Fi can still have no internet, so
/// requests keep their own timeouts and error states regardless.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);
  try {
    yield online(await connectivity.checkConnectivity());
  } on Object {
    yield true;
  }
  yield* connectivity.onConnectivityChanged.map(online);
});

final isOfflineProvider = Provider<bool>((ref) => ref.watch(connectivityProvider).value == false);
