import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../shared/services/preferences.dart';
import '../config/env.dart';
import 'surfaces.dart';

/// Which map engine draws the maps.
///
/// Google's, when a Maps key for this platform was built in (and, on iOS,
/// handed to the SDK at launch): the same maps people know, with satellite
/// imagery. Without one, the app's own key-free maps (OpenStreetMap-style
/// tiles), so a build never breaks for want of a key. Tests use the latter.
class GoogleMapsSetup {
  const GoogleMapsSetup._();

  static bool _ready = false;
  static bool get ready => _ready;

  static const _channel = MethodChannel('ai.akarat.app/maps');

  /// Once, before the first frame. Android reads its key from the manifest;
  /// iOS takes it here. If the iOS hand-over fails, the key-free maps stay
  /// on rather than a map crashing later.
  static Future<void> init() async {
    final key = Env.googleMapsKey;
    if (key.isEmpty) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        if (await _channel.invokeMethod<bool>('provideKey', key) != true) return;
      } on Object {
        return;
      }
    }
    _ready = true;
  }
}

/// Whether maps are Google's. See [GoogleMapsSetup].
final googleMapsProvider = Provider<bool>((ref) => GoogleMapsSetup.ready);

/// The street map, or satellite imagery with street names over it.
enum MapLayer { map, satellite }

/// The chosen layer, shared by every map and remembered between launches.
final mapLayerProvider = NotifierProvider<MapLayerNotifier, MapLayer>(MapLayerNotifier.new);

class MapLayerNotifier extends Notifier<MapLayer> {
  @override
  MapLayer build() => ref.read(preferencesProvider).mapLayer == 'satellite' ? MapLayer.satellite : MapLayer.map;

  Future<void> toggle() async {
    state = state == MapLayer.map ? MapLayer.satellite : MapLayer.map;
    await ref.read(preferencesProvider).setMapLayer(state.name);
  }
}

/// A white pill on a map that switches it to the other view: "Satellite"
/// on the street map, "Map" on the satellite view. Only on Google's maps;
/// the key-free maps have no imagery to switch to.
class MapLayerButton extends ConsumerWidget {
  const MapLayerButton({super.key, this.compact = false});

  /// A square icon button the size of Explore's filter button, for a row
  /// with no room for a label.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(googleMapsProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    final satellite = ref.watch(mapLayerProvider) == MapLayer.satellite;
    void toggle() {
      unawaited(HapticFeedback.selectionClick());
      unawaited(ref.read(mapLayerProvider.notifier).toggle());
    }

    if (compact) {
      return SquareIconButton(
        icon: satellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
        tooltip: satellite ? l.a11yMapViewMap : l.a11yMapViewSatellite,
        style: SquareStyle.onImage,
        size: 52,
        onTap: () => unawaited(ref.read(mapLayerProvider.notifier).toggle()),
      );
    }
    const ink = Color(0xFF16201D);
    return Semantics(
      button: true,
      toggled: satellite,
      label: satellite ? l.a11yMapViewMap : l.a11yMapViewSatellite,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: Radii.chip,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        child: InkWell(
          borderRadius: Radii.chip,
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(satellite ? Icons.map_rounded : Icons.satellite_alt_rounded, size: 17, color: ink),
                const SizedBox(width: Space.iconGap),
                Text(satellite ? l.mapViewMap : l.mapViewSatellite, style: context.type.pill.copyWith(color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
