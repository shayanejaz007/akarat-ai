import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../utils/geo.dart';

/// Why the phone's position could not be read.
enum LocateProblem { servicesOff, denied, failed }

/// Where the phone is, or why not.
typedef LocateResult = ({LatLngPoint? at, LocateProblem? problem});

/// Reads the phone's position, asking for permission the first time. Only
/// ever called from the "my location" button on a map: the position moves
/// that map and is not stored or sent anywhere.
class Locator {
  const Locator();

  Future<LocateResult> find() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (at: null, problem: LocateProblem.servicesOff);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return (at: null, problem: LocateProblem.denied);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return (at: LatLngPoint(p.latitude, p.longitude), problem: null);
    } on Object {
      return (at: null, problem: LocateProblem.failed);
    }
  }
}

/// Overridable, so tests never touch the device's location.
final locatorProvider = Provider<Locator>((ref) => const Locator());

/// A round white button on a map that finds the phone and hands the point
/// to [onFound]; the map moves there. A refusal is explained in a snackbar.
class LocateButton extends ConsumerStatefulWidget {
  const LocateButton({super.key, required this.onFound});
  final ValueChanged<LatLngPoint> onFound;

  @override
  ConsumerState<LocateButton> createState() => _LocateButtonState();
}

class _LocateButtonState extends ConsumerState<LocateButton> {
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(HapticFeedback.selectionClick());
    setState(() => _busy = true);
    final r = await ref.read(locatorProvider).find();
    if (!mounted) return;
    setState(() => _busy = false);
    final at = r.at;
    if (at != null) {
      widget.onFound(at);
      return;
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(switch (r.problem) {
          LocateProblem.servicesOff => l.mapLocateOff,
          LocateProblem.denied => l.mapLocateDenied,
          _ => l.mapLocateFailed,
        }),
        action: r.problem == LocateProblem.denied
            ? SnackBarAction(label: l.mapLocateSettings, onPressed: () => unawaited(Geolocator.openAppSettings()))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF16201D);
    return Semantics(
      button: true,
      label: context.l10n.mapLocateMe,
      excludeSemantics: true,
      child: Tooltip(
        message: context.l10n.mapLocateMe,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => unawaited(_go()),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                      )
                    : const Icon(Icons.my_location_rounded, size: 22, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "you are here" dot for the key-free maps (Google draws its own).
class HereDot extends StatelessWidget {
  const HereDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A73E8),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
    ),
  );
}

/// Space the button keeps from the map's edge.
const locateInset = Space.sm;
