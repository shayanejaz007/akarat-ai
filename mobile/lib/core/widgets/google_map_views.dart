import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../shared/models/listing.dart';
import '../utils/formatters.dart';
import '../utils/geo.dart';
import 'map_layer.dart';
import 'map_pin_images.dart';
import 'maps.dart' show MapPins, groupPins, mapTilesProvider;

/// The maps drawn by Google's native SDK, used when a Maps key is built in
/// (see [GoogleMapsSetup]): the same pins, clusters and behaviour as the
/// key-free maps in maps.dart, plus satellite imagery. Map loads in the
/// mobile SDKs are free.

const _jordan = LatLng(31.25, 36.2);

/// A calmer Google map for property: shops and transit icons off, so the
/// price pins stand out. Applies to the satellite view's labels too.
const _lightStyle = '''
[
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]''';

/// The street map in the dark theme, in the app's own dark greens.
const _darkStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#161616"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#a6a6a6"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b0b0b"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#3a3a3a"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1c1c1c"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#17221d"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#262626"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#111111"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#363636"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1418"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5f6b72"}]}
]''';

String _style(BuildContext context, MapLayer layer) =>
    layer == MapLayer.map && Theme.of(context).brightness == Brightness.dark ? _darkStyle : _lightStyle;

MapType _type(MapLayer layer) => layer == MapLayer.satellite ? MapType.hybrid : MapType.normal;

/// Draws pins for one map at this screen's density and text size.
MapPinImages _imagesFor(BuildContext context, MapPinImages? current) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.2);
  final style = context.text.labelMedium!;
  if (current != null && current.devicePixelRatio == dpr && current.textScale == scale && current.textStyle == style) {
    return current;
  }
  return MapPinImages(devicePixelRatio: dpr, textStyle: style, textScale: scale);
}

LatLngBounds _bounds(Iterable<Listing> pins) {
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final l in pins) {
    south = math.min(south, l.lat!);
    north = math.max(north, l.lat!);
    west = math.min(west, l.lng!);
    east = math.max(east, l.lng!);
  }
  return LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east));
}

/// Moves the camera without letting a map that is not laid out yet (no size
/// for bounds) throw.
void _move(GoogleMapController? map, CameraUpdate update, {bool animate = false}) {
  if (map == null) return;
  final done = animate ? map.animateCamera(update) : map.moveCamera(update);
  unawaited(done.catchError((Object _) {}));
}

/// Explore's map on Google: see `ListingsMap`.
class GoogleListingsMap extends ConsumerStatefulWidget {
  const GoogleListingsMap({
    super.key,
    required this.listings,
    required this.lang,
    required this.onSelect,
    this.selected,
    this.focus,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final List<Listing> listings;
  final String lang;
  final Listing? selected;
  final ValueChanged<Listing?> onSelect;
  final Listing? focus;
  final double topInset;
  final double bottomInset;

  @override
  ConsumerState<GoogleListingsMap> createState() => _GoogleListingsMapState();
}

class _GoogleListingsMapState extends ConsumerState<GoogleListingsMap> {
  GoogleMapController? _map;
  String _fittedFor = '';

  /// The camera's zoom, followed while it moves.
  double _zoom = 7;

  /// The zoom the pins were grouped for: regrouped when the camera settles,
  /// not on every frame of a pinch.
  double _groupedAt = 7;

  MapPinImages? _images;
  final _icons = <String, PinImage>{};
  final _pending = <String>{};

  List<Listing> get _pinned => widget.listings.where((l) => l.hasCoordinates).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final images = _imagesFor(context, _images);
    if (!identical(images, _images)) {
      _images = images;
      _icons.clear();
      _pending.clear();
    }
  }

  @override
  void didUpdateWidget(GoogleListingsMap old) {
    super.didUpdateWidget(old);
    _fit();
    final f = widget.focus;
    if (f != null && f.hasCoordinates && f.id != old.focus?.id) {
      // The map's padding keeps the pin in the clear space between the
      // header and the cards.
      _move(_map, CameraUpdate.newLatLngZoom(LatLng(f.lat!, f.lng!), math.max(_zoom, 12)), animate: true);
    }
  }

  /// Frames the pins when the set of pins changes (new filters), not on
  /// every rebuild, so the reader's own panning is left alone.
  void _fit() {
    final map = _map;
    if (map == null) return;
    final pins = _pinned;
    final signature = pins.map((l) => l.id).join(',');
    if (signature == _fittedFor) return;
    _fittedFor = signature;
    if (pins.isEmpty) {
      _move(map, CameraUpdate.newLatLngZoom(_jordan, 7));
      return;
    }
    final b = _bounds(pins);
    final tight =
        b.northeast.latitude - b.southwest.latitude < 0.01 && b.northeast.longitude - b.southwest.longitude < 0.01;
    _move(
      map,
      tight
          ? CameraUpdate.newLatLngZoom(
              LatLng(
                (b.northeast.latitude + b.southwest.latitude) / 2,
                (b.northeast.longitude + b.southwest.longitude) / 2,
              ),
              13,
            )
          : CameraUpdate.newLatLngBounds(b, 48),
    );
  }

  void _zoomInto(List<Listing> members) {
    final b = _bounds(members);
    // Points too close to part on screen: step in around their centre.
    if (b.northeast.latitude - b.southwest.latitude < 0.0005 &&
        b.northeast.longitude - b.southwest.longitude < 0.0005) {
      _move(
        _map,
        CameraUpdate.newLatLngZoom(
          LatLng(
            (b.northeast.latitude + b.southwest.latitude) / 2,
            (b.northeast.longitude + b.southwest.longitude) / 2,
          ),
          math.min(_zoom + 3, 18),
        ),
        animate: true,
      );
      return;
    }
    _move(_map, CameraUpdate.newLatLngBounds(b, 64), animate: true);
  }

  Color _colour(Listing l) => l.isClosed ? MapPins.closed : (l.isRent ? MapPins.rent : MapPins.sale);

  /// Draws any pins not drawn yet, then shows them.
  void _request(Map<String, Future<PinImage> Function()> wanted) {
    final images = _images;
    final missing = [
      for (final e in wanted.entries)
        if (!_icons.containsKey(e.key) && _pending.add(e.key)) e,
    ];
    if (missing.isEmpty) return;
    unawaited(
      Future.wait([for (final e in missing) e.value().then((img) => MapEntry(e.key, img))]).then((drawn) {
        if (!mounted || !identical(images, _images)) return;
        setState(() {
          _icons.addEntries(drawn);
          _pending.removeAll(drawn.map((e) => e.key));
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layer = ref.watch(mapLayerProvider);
    final images = _images!;
    final pins = _pinned;
    final selected = pins.where((l) => l.id == widget.selected?.id).firstOrNull;
    // The selected pin always stands alone, drawn on top.
    final groups = groupPins(pins.where((l) => l.id != selected?.id).toList(), _groupedAt);

    final wanted = <String, Future<PinImage> Function()>{};
    String priceKey(Listing l, {required bool chosen}) {
      final label = Fmt.compactPrice(l.priceJod, lang: widget.lang, currency: false);
      final bg = _colour(l);
      final fg = l.isClosed ? Colors.white : (l.isRent ? MapPins.rentText : MapPins.saleText);
      final key = 'p|$label|${bg.toARGB32()}|$chosen';
      wanted[key] = () => images.price(label, background: bg, foreground: fg, selected: chosen);
      return key;
    }

    String clusterKey(List<Listing> members) {
      final allRent = members.every((l) => l.isRent);
      final mixed = !allRent && members.any((l) => l.isRent);
      final key = 'c|${members.length}|$allRent|$mixed';
      wanted[key] = () => images.cluster(
        members.length,
        background: allRent ? MapPins.rent : MapPins.sale,
        foreground: allRent ? MapPins.rentText : MapPins.saleText,
        ring: mixed ? MapPins.rent : null,
      );
      return key;
    }

    Marker? price(Listing l, {required bool chosen}) {
      final img = _icons[priceKey(l, chosen: chosen)];
      if (img == null) return null;
      return Marker(
        markerId: MarkerId(l.id),
        position: LatLng(l.lat!, l.lng!),
        icon: img.icon,
        anchor: img.anchor,
        consumeTapEvents: true,
        zIndexInt: chosen ? 2 : 1,
        // Read out by screen readers; never shown, as taps are taken here.
        infoWindow: InfoWindow(
          title: '${Fmt.price(l.priceJod, lang: widget.lang, rent: l.isRent)}, ${l.title(widget.lang)}',
        ),
        onTap: () => widget.onSelect(l),
      );
    }

    final markers = <Marker>{
      for (final g in groups)
        if (g.length == 1)
          ?price(g.single, chosen: false)
        else if (_icons[clusterKey(g)] case final img?)
          Marker(
            markerId: MarkerId('cluster:${g.map((l) => l.id).join(',')}'),
            position: LatLng(
              g.map((l) => l.lat!).reduce((a, b) => a + b) / g.length,
              g.map((l) => l.lng!).reduce((a, b) => a + b) / g.length,
            ),
            icon: img.icon,
            anchor: img.anchor,
            consumeTapEvents: true,
            zIndexInt: 1,
            infoWindow: InfoWindow(title: l10n.mapCluster(g.length)),
            onTap: () => _zoomInto(g),
          ),
      if (selected != null) ?price(selected, chosen: true),
    };
    _request(wanted);

    return GoogleMap(
      initialCameraPosition: const CameraPosition(target: _jordan, zoom: 7),
      onMapCreated: (map) {
        _map = map;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      },
      mapType: _type(layer),
      style: _style(context, layer),
      // Google's logo and the framing stay clear of the floating controls.
      padding: EdgeInsets.only(top: widget.topInset, bottom: widget.bottomInset),
      markers: markers,
      circles: {
        for (final l in pins.where((l) => !l.isExactLocation))
          Circle(
            circleId: CircleId(l.id),
            center: LatLng(l.lat!, l.lng!),
            radius: Geo.blurRadiusMetres.toDouble(),
            fillColor: _colour(l).withValues(alpha: 0.12),
            strokeColor: _colour(l).withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
      },
      onCameraMove: (camera) => _zoom = camera.zoom,
      onCameraIdle: () {
        if ((_zoom - _groupedAt).abs() > 0.05) setState(() => _groupedAt = _zoom);
      },
      onTap: (_) => widget.onSelect(null),
      minMaxZoomPreference: const MinMaxZoomPreference(5, 19),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      indoorViewEnabled: false,
    );
  }
}

/// A listing's own map on Google: see `LocationPreview`.
class GoogleLocationPreview extends ConsumerStatefulWidget {
  const GoogleLocationPreview({super.key, required this.lat, required this.lng, required this.exact});
  final double lat;
  final double lng;
  final bool exact;

  @override
  ConsumerState<GoogleLocationPreview> createState() => _GoogleLocationPreviewState();
}

class _GoogleLocationPreviewState extends ConsumerState<GoogleLocationPreview> {
  MapPinImages? _images;
  PinImage? _pin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final images = _imagesFor(context, _images);
    if (identical(images, _images)) return;
    _images = images;
    if (widget.exact) {
      unawaited(
        images.place(MapPins.sale).then((pin) {
          if (mounted) setState(() => _pin = pin);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layer = ref.watch(mapLayerProvider);
    final at = LatLng(widget.lat, widget.lng);
    final pin = _pin;
    return Stack(
      fit: StackFit.expand,
      children: [
        // A still picture of the map inside the scrolling page: the page
        // scrolls over it, and on Android it is drawn once (lite mode).
        IgnorePointer(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: at, zoom: widget.exact ? 16 : 14.6),
            liteModeEnabled: defaultTargetPlatform == TargetPlatform.android,
            mapType: _type(layer),
            style: _style(context, layer),
            markers: {
              if (widget.exact && pin != null)
                Marker(markerId: const MarkerId('place'), position: at, icon: pin.icon, anchor: pin.anchor),
            },
            circles: {
              if (!widget.exact)
                Circle(
                  circleId: const CircleId('area'),
                  center: at,
                  radius: Geo.blurRadiusMetres.toDouble(),
                  fillColor: c.emerald.withValues(alpha: 0.18),
                  strokeColor: c.emerald,
                  strokeWidth: 2,
                ),
            },
            scrollGesturesEnabled: false,
            zoomGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),
        ),
        const PositionedDirectional(top: 8, end: 8, child: MapLayerButton()),
      ],
    );
  }
}

/// The listing form's pin picker on Google: see `PinPicker`. The satellite
/// view lets an owner find their own building.
class GooglePinPicker extends ConsumerStatefulWidget {
  const GooglePinPicker({super.key, required this.initial, required this.center, required this.onChanged});
  final LatLngPoint? initial;
  final LatLngPoint center;
  final ValueChanged<LatLngPoint> onChanged;

  @override
  ConsumerState<GooglePinPicker> createState() => _GooglePinPickerState();
}

class _GooglePinPickerState extends ConsumerState<GooglePinPicker> {
  GoogleMapController? _map;
  late LatLngPoint? _pin = widget.initial;
  MapPinImages? _images;
  PinImage? _icon;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final images = _imagesFor(context, _images);
    if (identical(images, _images)) return;
    _images = images;
    unawaited(
      images.place(MapPins.sale).then((icon) {
        if (mounted) setState(() => _icon = icon);
      }),
    );
  }

  @override
  void didUpdateWidget(GooglePinPicker old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) _pin = widget.initial;
    if (widget.center != old.center && widget.initial == null) {
      _move(_map, CameraUpdate.newLatLngZoom(LatLng(widget.center.lat, widget.center.lng), 12), animate: true);
    }
  }

  void _set(LatLng p) {
    final point = LatLngPoint(p.latitude, p.longitude);
    setState(() => _pin = point);
    widget.onChanged(point);
  }

  @override
  Widget build(BuildContext context) {
    final layer = ref.watch(mapLayerProvider);
    final start = _pin ?? widget.center;
    final pin = _pin;
    final icon = _icon;
    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: LatLng(start.lat, start.lng), zoom: _pin == null ? 12 : 16),
          onMapCreated: (map) => _map = map,
          mapType: _type(layer),
          style: _style(context, layer),
          markers: {
            if (pin != null && icon != null)
              Marker(
                markerId: const MarkerId('pin'),
                position: LatLng(pin.lat, pin.lng),
                icon: icon.icon,
                anchor: icon.anchor,
                draggable: true,
                onDragEnd: _set,
              ),
          },
          // Tap to drop the pin, as on the website; dragging moves it too.
          onTap: _set,
          // Inside a scrolling form, the map takes every touch on it.
          gestureRecognizers: const {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
        ),
        const PositionedDirectional(top: 8, end: 8, child: MapLayerButton()),
      ],
    );
  }
}

/// Whether Google draws the maps here: a key is built in and tiles are on
/// (tests turn tiles off).
bool useGoogleMaps(WidgetRef ref) => ref.watch(googleMapsProvider) && ref.watch(mapTilesProvider);
