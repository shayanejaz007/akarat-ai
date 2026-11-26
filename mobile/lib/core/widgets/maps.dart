import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/tokens.dart';
import '../../shared/models/listing.dart';
import '../config/env.dart';
import '../utils/geo.dart';
import 'google_map_views.dart';
import 'locate.dart';

/// Map widgets. With a Google Maps key built in, Google's native maps draw
/// them (google_map_views.dart), with satellite imagery; without one, the
/// OpenStreetMap-style raster tiles from [Env.mapTileUrl] below, which need
/// no key. Both draw the same pins and behave the same way.
///
/// Only the PUBLISHABLE point from `properties.lat/lng` is ever drawn. When
/// the owner chose "approximate", that point is already displaced by up to
/// 300 m and is drawn with a shaded circle, so the map never implies a
/// precision the data does not have.

/// Whether tiles are fetched. Tests turn this off: no network there.
final mapTilesProvider = Provider<bool>((ref) => true);

/// Pin colours. Fixed rather than themed: they have to mean the same thing
/// on light and dark maps.
class MapPins {
  const MapPins._();
  static const sale = Color(0xFF2A2A2C);
  static const saleText = Colors.white;
  static const rent = Color(0xFFE0AE45);
  static const rentText = Color(0xFF2A1E05);
  static const daily = Color(0xFF8A5D17);
  static const dailyText = Colors.white;

  static Color of(Listing l) => l.isClosed ? closed : (l.isDaily ? daily : (l.isRent ? rent : sale));
  static Color textOf(Listing l) =>
      l.isClosed ? Colors.white : (l.isDaily ? dailyText : (l.isRent ? rentText : saleText));
  static const closed = Color(0xFF8E9893);
}

const _jordan = LatLng(31.25, 36.2);

/// Pins closer than a pin's width on screen at [zoom], grouped. Greedy, in
/// screen pixels (256-pixel tiles, as both map engines use): cheap enough to
/// redo whenever the zoom settles.
/// Listings on the very same spot (a building, or an area's centre) set
/// around it, 30 m apart a ring at a time, so that zooming in always parts
/// them and each keeps a pin of its own. Only where they are drawn moves.
List<Listing> spreadPins(List<Listing> pins) {
  final seen = <String, int>{};
  return [
    for (final l in pins)
      () {
        final key = '${l.lat!.toStringAsFixed(5)},${l.lng!.toStringAsFixed(5)}';
        final k = seen[key] ?? 0;
        seen[key] = k + 1;
        if (k == 0) return l;
        final ring = 1 + (k - 1) ~/ 8;
        final angle = ((k - 1) % 8) * (math.pi / 4) + ring * 0.4;
        final metres = 30.0 * ring;
        final lat = l.lat! + metres * math.cos(angle) / 111320;
        final lng = l.lng! + metres * math.sin(angle) / (111320 * math.cos(l.lat! * math.pi / 180));
        return l.at(lat, lng);
      }(),
  ];
}

/// Every listing keeps a price pin of its own at every zoom; nothing is
/// merged into a numbered circle. Zoomed out, pins in a busy area overlap
/// until the map is zoomed in.

Widget _tiles(BuildContext context, WidgetRef ref) {
  if (!ref.watch(mapTilesProvider)) return const SizedBox.shrink();
  final dark = Theme.of(context).brightness == Brightness.dark;
  return TileLayer(
    urlTemplate: Env.mapTileUrl,
    userAgentPackageName: 'ai.akarat.app',
    maxNativeZoom: 19,
    tileBuilder: dark ? darkModeTileBuilder : null,
  );
}

Widget _attribution(BuildContext context) => Align(
  alignment: AlignmentDirectional.bottomEnd,
  child: Container(
    margin: const EdgeInsets.all(4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
    child: const Text(
      '© OpenStreetMap',
      textDirection: TextDirection.ltr,
      style: TextStyle(fontSize: 10, color: Color(0xFF333333)),
    ),
  ),
);

/// Every listing with a location, as price pins: forest for sale, gold for
/// rent, grey once sold or rented. Pins that would overlap at the current
/// zoom merge into a numbered bubble; tapping it zooms in until they part.
/// Tapping a pin selects it; tapping the map clears the selection.
class ListingsMap extends ConsumerWidget {
  const ListingsMap({
    super.key,
    required this.listings,
    required this.lang,
    required this.onSelect,
    this.selected,
    this.focus,
    this.bottomInset = 0,
    this.topInset = 0,
  });

  final List<Listing> listings;
  final String lang;
  final Listing? selected;
  final ValueChanged<Listing?> onSelect;

  /// When this changes (a card was swiped to), the map brings its pin into
  /// the clear part of the screen, between the floating controls.
  final Listing? focus;

  /// Room taken by floating controls, so fitted pins are not hidden under them.
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (useGoogleMaps(ref)) {
      return GoogleListingsMap(
        listings: listings,
        lang: lang,
        onSelect: onSelect,
        selected: selected,
        focus: focus,
        topInset: topInset,
        bottomInset: bottomInset,
      );
    }
    return _TileListingsMap(
      listings: listings,
      lang: lang,
      onSelect: onSelect,
      selected: selected,
      focus: focus,
      topInset: topInset,
      bottomInset: bottomInset,
    );
  }
}

class _TileListingsMap extends ConsumerStatefulWidget {
  const _TileListingsMap({
    required this.listings,
    required this.lang,
    required this.onSelect,
    this.selected,
    this.focus,
    this.bottomInset = 0,
    this.topInset = 0,
  });

  final List<Listing> listings;
  final String lang;
  final Listing? selected;
  final ValueChanged<Listing?> onSelect;

  /// When this changes (a card was swiped to), the map brings its pin into
  /// the clear part of the screen, between the floating controls.
  final Listing? focus;

  /// Room taken by floating controls, so fitted pins are not hidden under them.
  final double topInset;
  final double bottomInset;

  @override
  ConsumerState<_TileListingsMap> createState() => _TileListingsMapState();
}

class _TileListingsMapState extends ConsumerState<_TileListingsMap> {
  LatLng? _here;
  final _controller = MapController();
  bool _ready = false;
  String _fittedFor = '';
  double _zoom = 7;

  List<Listing> get _pinned => spreadPins(widget.listings.where((l) => l.hasCoordinates).toList());

  @override
  void didUpdateWidget(_TileListingsMap old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    _fit();
    final f = widget.focus;
    if (f != null && f.hasCoordinates && f.id != old.focus?.id) {
      _controller.move(
        LatLng(f.lat!, f.lng!),
        math.max(_controller.camera.zoom, 12),
        // Centre the pin in the space between the header and the cards.
        offset: Offset(0, (widget.topInset - widget.bottomInset) / 2),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Frames the pins whenever the set of pins changes (new filters), but
  /// not on every rebuild, so a reader's own panning is left alone.
  void _fit() {
    final pins = _pinned;
    final signature = pins.map((l) => l.id).join(',');
    if (signature == _fittedFor) return;
    _fittedFor = signature;
    final padding = EdgeInsets.fromLTRB(48, widget.topInset + 32, 48, widget.bottomInset + 32);
    if (pins.isEmpty) {
      _controller.move(_jordan, 7);
    } else if (pins.length == 1) {
      _controller.move(LatLng(pins.first.lat!, pins.first.lng!), 13);
    } else {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([for (final l in pins) LatLng(l.lat!, l.lng!)]),
          padding: padding,
          maxZoom: 14,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pins = _pinned;
    final selected = pins.where((l) => l.id == widget.selected?.id).firstOrNull;
    // The selected pin is drawn last, on top.
    final others = pins.where((l) => l.id != selected?.id);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _jordan,
        initialZoom: 7,
        minZoom: 5,
        maxZoom: 18,
        backgroundColor: c.surfaceMuted,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () {
          _ready = true;
          _fit();
        },
        onTap: (_, _) => widget.onSelect(null),
        onPositionChanged: (camera, _) {
          if ((camera.zoom - _zoom).abs() < 0.05) return;
          // Redraw after the frame: this can fire while the map lays out.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _zoom = camera.zoom);
          });
        },
      ),
      children: [
        _tiles(context, ref),
        CircleLayer(
          circles: [
            for (final l in pins.where((l) => !l.isExactLocation))
              CircleMarker(
                point: LatLng(l.lat!, l.lng!),
                radius: Geo.blurRadiusMetres,
                useRadiusInMeter: true,
                color: _colour(l).withValues(alpha: 0.12),
                borderColor: _colour(l).withValues(alpha: 0.5),
                borderStrokeWidth: 1,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final l in others) _priceMarker(context, l, selected: false, scaler: scaler),
            if (selected != null) _priceMarker(context, selected, selected: true, scaler: scaler),
          ],
        ),
        if (_here case final h?)
          MarkerLayer(
            markers: [Marker(point: h, width: 20, height: 20, child: const HereDot())],
          ),
        _attribution(context),
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: locateInset, bottom: widget.bottomInset + locateInset),
            child: LocateButton(
              onFound: (at) {
                final p = LatLng(at.lat, at.lng);
                setState(() => _here = p);
                _controller.move(p, 16);
              },
            ),
          ),
        ),
      ],
    );
  }

  Color _colour(Listing l) => MapPins.of(l);

  Marker _priceMarker(BuildContext context, Listing l, {required bool selected, required TextScaler scaler}) {
    // Short on the map: the currency is the same on every pin.
    final label = l.pinPrice(widget.lang);
    final style = context.text.labelMedium!.copyWith(fontWeight: FontWeight.w700, fontSize: selected ? 14 : 13);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    // Padding (10 + 10), border (up to 2.5 a side) and a little slack, so
    // the label is never clipped ("73.5K" losing its K).
    final width = painter.width.ceilToDouble() + (selected ? 34 : 30);
    final height = (selected ? 34.0 : 30.0) * scaler.scale(1).clamp(1.0, 1.2) + 7;
    final bg = _colour(l);
    final fg = MapPins.textOf(l);
    return Marker(
      point: LatLng(l.lat!, l.lng!),
      width: math.max(width, 44),
      height: height,
      // The pointer's tip sits on the point.
      alignment: Alignment.topCenter,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${l.priceText(widget.lang)}, ${l.title(widget.lang)}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => widget.onSelect(l),
          child: _PricePin(
            label: label,
            background: bg,
            foreground: fg,
            selected: selected,
            style: style,
            scaler: scaler,
          ),
        ),
      ),
    );
  }
}

class _PricePin extends StatelessWidget {
  const _PricePin({
    required this.label,
    required this.background,
    required this.foreground,
    required this.selected,
    required this.style,
    required this.scaler,
  });

  final TextScaler scaler;
  final String label;
  final Color background;
  final Color foreground;
  final bool selected;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Pins pop up from their point when they appear, and swell when chosen.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: selected ? 1.06 : 1),
      duration: Motion.of(context, Motion.normal),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, alignment: Alignment.bottomCenter, child: child),
      child: _pin(context),
    );
  }

  Widget _pin(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: Radii.chip,
              border: Border.all(color: Colors.white, width: selected ? 2.5 : 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.35 : 0.22),
                  blurRadius: selected ? 6 : 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              textScaler: scaler,
              textDirection: TextDirection.ltr,
              style: style.copyWith(color: foreground),
            ),
          ),
        ),
        CustomPaint(size: const Size(12, 7), painter: _PointerPainter(background)),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  _PointerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color;
}

/// A small, still preview on the detail page.
class LocationPreview extends ConsumerWidget {
  const LocationPreview({super.key, required this.lat, required this.lng, required this.exact});
  final double lat;
  final double lng;
  final bool exact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => useGoogleMaps(ref)
      ? GoogleLocationPreview(lat: lat, lng: lng, exact: exact)
      : _TileLocationPreview(lat: lat, lng: lng, exact: exact);
}

class _TileLocationPreview extends ConsumerWidget {
  const _TileLocationPreview({required this.lat, required this.lng, required this.exact});
  final double lat;
  final double lng;
  final bool exact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final at = LatLng(lat, lng);
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: at,
          initialZoom: exact ? 15.5 : 14.2,
          backgroundColor: c.surfaceMuted,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          _tiles(context, ref),
          if (!exact)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: at,
                  radius: Geo.blurRadiusMetres,
                  useRadiusInMeter: true,
                  color: c.emerald.withValues(alpha: 0.18),
                  borderColor: c.emerald,
                  borderStrokeWidth: 2,
                ),
              ],
            )
          else
            MarkerLayer(
              markers: [
                Marker(
                  point: at,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on_rounded, size: 40, color: MapPins.sale),
                ),
              ],
            ),
          _attribution(context),
        ],
      ),
    );
  }
}

/// Lets an owner drop a pin by tapping the map; tapping again moves it.
///
/// On Google's maps it opens on satellite imagery with street names, with a
/// switch to the street map ([pinLayerProvider]); [centerZoom] is how close
/// it looks at [center] (the chosen place) while no pin is placed.
class PinPicker extends ConsumerWidget {
  const PinPicker({
    super.key,
    required this.initial,
    required this.center,
    required this.onChanged,
    this.centerZoom = 12,
  });
  final LatLngPoint? initial;
  final LatLngPoint center;
  final ValueChanged<LatLngPoint> onChanged;
  final double centerZoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) => useGoogleMaps(ref)
      ? GooglePinPicker(initial: initial, center: center, onChanged: onChanged, centerZoom: centerZoom)
      : _TilePinPicker(initial: initial, center: center, onChanged: onChanged);
}

class _TilePinPicker extends ConsumerStatefulWidget {
  const _TilePinPicker({required this.initial, required this.center, required this.onChanged});
  final LatLngPoint? initial;
  final LatLngPoint center;
  final ValueChanged<LatLngPoint> onChanged;

  @override
  ConsumerState<_TilePinPicker> createState() => _TilePinPickerState();
}

class _TilePinPickerState extends ConsumerState<_TilePinPicker> {
  final _controller = MapController();
  LatLng? _here;
  late LatLngPoint? _pin = widget.initial;
  bool _ready = false;

  @override
  void didUpdateWidget(_TilePinPicker old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) _pin = widget.initial;
    if (_ready && widget.center != old.center && widget.initial == null) {
      _controller.move(LatLng(widget.center.lat, widget.center.lng), 12);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(LatLng p) {
    final point = LatLngPoint(p.latitude, p.longitude);
    setState(() => _pin = point);
    widget.onChanged(point);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final start = _pin ?? widget.center;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: LatLng(start.lat, start.lng),
        initialZoom: _pin == null ? 12 : 16,
        backgroundColor: c.surfaceMuted,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () => _ready = true,
        onTap: (_, p) => _set(p),
      ),
      children: [
        _tiles(context, ref),
        if (_pin != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(_pin!.lat, _pin!.lng),
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on_rounded, size: 44, color: MapPins.sale),
              ),
            ],
          ),
        if (_here case final h?)
          MarkerLayer(
            markers: [Marker(point: h, width: 20, height: 20, child: const HereDot())],
          ),
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8, bottom: 28),
            child: LocateButton(
              onFound: (at) {
                final p = LatLng(at.lat, at.lng);
                setState(() => _here = p);
                _controller.move(p, 17);
              },
            ),
          ),
        ),
        _attribution(context),
      ],
    );
  }
}

/// Opens the platform's maps app at a point: the "Open in Maps" action.
Future<void> openInMaps(double lat, double lng, String label) async {
  final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Street View at a point, in Google Maps (the app when installed). Google
/// finds the nearest panorama. Free, with no key: it is Google's own app.
Uri streetViewUri(double lat, double lng) =>
    Uri.https('www.google.com', '/maps/@', {'api': '1', 'map_action': 'pano', 'viewpoint': '$lat,$lng'});

Future<void> openStreetView(double lat, double lng) =>
    launchUrl(streetViewUri(lat, lng), mode: LaunchMode.externalApplication);
