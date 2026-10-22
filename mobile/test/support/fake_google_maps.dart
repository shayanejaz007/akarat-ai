import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// Stands in for Google's native map in widget tests: no platform view, but
/// it keeps what the app asked the map to show (markers, circles, the map
/// type, camera moves) and can play back taps.
class FakeGoogleMapsPlatform extends GoogleMapsFlutterPlatform {
  /// The latest configuration (map type, style, padding...).
  MapConfiguration configuration = const MapConfiguration();
  final markers = <MarkerId, Marker>{};
  final circles = <CircleId, Circle>{};
  final cameraUpdates = <CameraUpdate>[];
  int? mapId;
  final _created = <int>{};

  final _markerTaps = StreamController<MarkerTapEvent>.broadcast();
  final _mapTaps = StreamController<MapTapEvent>.broadcast();
  final _cameraIdle = StreamController<CameraIdleEvent>.broadcast();
  final _cameraMove = StreamController<CameraMoveEvent>.broadcast();

  /// Ends the event streams; call from tearDown.
  Future<void> close() async {
    await _markerTaps.close();
    await _mapTaps.close();
    await _cameraIdle.close();
    await _cameraMove.close();
  }

  /// As if the reader zoomed to [zoom] and let go.
  void zoomTo(double zoom) {
    _cameraMove.add(CameraMoveEvent(mapId!, CameraPosition(target: const LatLng(31.95, 35.86), zoom: zoom)));
    _cameraIdle.add(CameraIdleEvent(mapId!));
  }

  /// As if the reader tapped the marker [id].
  void tapMarker(String id) => _markerTaps.add(MarkerTapEvent(mapId!, MarkerId(id)));

  /// As if the reader tapped the map away from any marker.
  void tapMap() => _mapTaps.add(MapTapEvent(mapId!, const LatLng(31.9, 35.9)));

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    // Called on every rebuild; a real map view is created once.
    if (_created.add(creationId)) {
      mapId = creationId;
      configuration = mapConfiguration;
      markers.addEntries(mapObjects.markers.map((m) => MapEntry(m.markerId, m)));
      circles.addEntries(mapObjects.circles.map((c) => MapEntry(c.circleId, c)));
      WidgetsBinding.instance.addPostFrameCallback((_) => onPlatformViewCreated(creationId));
    }
    return const SizedBox.expand(key: ValueKey('fake-google-map'));
  }

  @override
  Future<void> init(int mapId) async {}

  @override
  Future<void> updateMapConfiguration(MapConfiguration update, {required int mapId}) async {
    configuration = configuration.applyDiff(update);
  }

  @override
  Future<void> updateMarkers(MarkerUpdates updates, {required int mapId}) async {
    updates.markerIdsToRemove.forEach(markers.remove);
    for (final m in [...updates.objectsToAdd, ...updates.objectsToChange]) {
      markers[m.markerId] = m;
    }
  }

  @override
  Future<void> updateCircles(CircleUpdates updates, {required int mapId}) async {
    updates.circleIdsToRemove.forEach(circles.remove);
    for (final c in [...updates.circlesToAdd, ...updates.circlesToChange]) {
      circles[c.circleId] = c;
    }
  }

  @override
  Future<void> updatePolygons(PolygonUpdates polygonUpdates, {required int mapId}) async {}

  @override
  Future<void> updatePolylines(PolylineUpdates polylineUpdates, {required int mapId}) async {}

  @override
  Future<void> updateTileOverlays({required Set<TileOverlay> newTileOverlays, required int mapId}) async {}

  @override
  Future<void> updateClusterManagers(ClusterManagerUpdates clusterManagerUpdates, {required int mapId}) async {}

  @override
  Future<void> updateGroundOverlays(GroundOverlayUpdates groundOverlayUpdates, {required int mapId}) async {}

  @override
  Future<void> updateHeatmaps(HeatmapUpdates heatmapUpdates, {required int mapId}) async {}

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate, {required int mapId}) async => cameraUpdates.add(cameraUpdate);

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate, {required int mapId}) async => cameraUpdates.add(cameraUpdate);

  @override
  Future<double> getZoomLevel({required int mapId}) async => 7;

  @override
  Stream<CameraMoveStartedEvent> onCameraMoveStarted({required int mapId}) => const Stream.empty();

  @override
  Stream<CameraMoveEvent> onCameraMove({required int mapId}) => _cameraMove.stream;

  @override
  Stream<CameraIdleEvent> onCameraIdle({required int mapId}) => _cameraIdle.stream;

  @override
  Stream<MarkerTapEvent> onMarkerTap({required int mapId}) => _markerTaps.stream;

  @override
  Stream<InfoWindowTapEvent> onInfoWindowTap({required int mapId}) => const Stream.empty();

  @override
  Stream<MarkerDragStartEvent> onMarkerDragStart({required int mapId}) => const Stream.empty();

  @override
  Stream<MarkerDragEvent> onMarkerDrag({required int mapId}) => const Stream.empty();

  @override
  Stream<MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) => const Stream.empty();

  @override
  Stream<PolylineTapEvent> onPolylineTap({required int mapId}) => const Stream.empty();

  @override
  Stream<PolygonTapEvent> onPolygonTap({required int mapId}) => const Stream.empty();

  @override
  Stream<CircleTapEvent> onCircleTap({required int mapId}) => const Stream.empty();

  @override
  Stream<PointOfInterestTapEvent> onPointOfInterestTap({required int mapId}) => const Stream.empty();

  @override
  Stream<MapTapEvent> onTap({required int mapId}) => _mapTaps.stream;

  @override
  Stream<MapLongPressEvent> onLongPress({required int mapId}) => const Stream.empty();

  @override
  Stream<ClusterTapEvent> onClusterTap({required int mapId}) => const Stream.empty();

  @override
  Stream<GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) => const Stream.empty();

  @override
  void dispose({required int mapId}) {}
}
