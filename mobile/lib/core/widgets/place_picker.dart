import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../shared/reference/places.dart';
import '../../shared/reference/places_provider.dart';

/// A form field showing the chosen place; tapping it opens [showPlacePicker].
///
/// [anyLabel] makes "no place" a choice (a filter: "Anywhere in Jordan").
/// [requireCity] keeps a governorate on its own from being chosen (a listing
/// or a request needs its town).
class PlaceField extends ConsumerWidget {
  const PlaceField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.anyLabel,
    this.requireCity = false,
    this.errorText,
  });

  final String label;
  final PlaceSel? value;
  final ValueChanged<PlaceSel?> onChanged;
  final String? anyLabel;
  final bool requireCity;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final places = ref.watch(placesNowProvider).places;
    final chosen = places.selLabel(value, context.lang);
    final empty = chosen.isEmpty;
    return Semantics(
      button: true,
      label: '$label: ${empty ? (anyLabel ?? l.placePickTitle) : chosen}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.field,
        onTap: () async {
          final picked = await showPlacePicker(context, current: value, anyLabel: anyLabel, requireCity: requireCity);
          if (picked != null) onChanged(picked.isEmpty ? null : picked);
        },
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.place_outlined),
            suffixIcon: const Icon(Icons.expand_more_rounded),
          ),
          child: Text(
            empty ? (anyLabel ?? l.placePickTitle) : chosen,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyLarge?.copyWith(color: empty ? context.colors.inkMuted : null),
          ),
        ),
      ),
    );
  }
}

/// Search or browse every place. Returns the choice, an empty [PlaceSel]
/// for [anyLabel], or null when dismissed.
Future<PlaceSel?> showPlacePicker(
  BuildContext context, {
  PlaceSel? current,
  String? anyLabel,
  bool requireCity = false,
}) => showModalBottomSheet<PlaceSel>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _PlaceSheet(current: current, anyLabel: anyLabel, requireCity: requireCity),
);

class _PlaceSheet extends ConsumerStatefulWidget {
  const _PlaceSheet({this.current, this.anyLabel, required this.requireCity});
  final PlaceSel? current;
  final String? anyLabel;
  final bool requireCity;

  @override
  ConsumerState<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<_PlaceSheet> {
  final _query = TextEditingController();
  // Browsing: the governorate, then the city, being looked inside.
  String? _gov;
  String? _city;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Place> _sorted(List<Place> list, String lang) =>
      [...list]..sort((a, b) => a.core != b.core ? (a.core ? -1 : 1) : a.label(lang).compareTo(b.label(lang)));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final state = ref.watch(placesNowProvider);
    final places = state.places;
    final q = _query.text.trim();

    void done(PlaceSel sel) => Navigator.of(context).pop(sel);

    final rows = <Widget>[];
    if (q.isNotEmpty) {
      final hits = places
          .search(q, lang: lang, limit: 30)
          .where(
            (h) => state.choosable(
              h.kind == PlaceKind.gov
                  ? places.gov(h.id)!
                  : h.kind == PlaceKind.city
                  ? places.city(h.id)!
                  : places.hood(h.id)!,
            ),
          )
          .take(20)
          .toList();
      if (hits.isEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(l.placeNoMatch, style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
          ),
        );
      }
      for (final h in hits) {
        rows.add(
          ListTile(
            leading: Icon(_icon(h.kind), color: c.emerald),
            title: Text(h.label),
            subtitle: h.path.isEmpty ? null : Text(h.path),
            onTap: () {
              if (h.kind == PlaceKind.gov && widget.requireCity) {
                setState(() {
                  _query.clear();
                  _gov = h.id;
                  _city = null;
                });
              } else {
                done(h.sel);
              }
            },
          ),
        );
      }
    } else if (_gov == null) {
      if (widget.anyLabel != null) {
        rows.add(
          ListTile(
            leading: Icon(Icons.public_rounded, color: c.emerald),
            title: Text(widget.anyLabel!),
            selected: widget.current == null || widget.current!.isEmpty,
            onTap: () => done(const PlaceSel()),
          ),
        );
      }
      rows.add(_Heading(l.placeGovernorates));
      for (final g in places.governorates) {
        rows.add(
          ListTile(
            leading: Icon(_icon(PlaceKind.gov), color: c.emerald),
            title: Text(g.label(lang)),
            selected: widget.current?.gov == g.id,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => setState(() => _gov = g.id),
          ),
        );
      }
    } else if (_city == null) {
      final g = places.gov(_gov);
      if (!widget.requireCity && g != null) {
        rows.add(
          ListTile(
            leading: Icon(Icons.select_all_rounded, color: c.emerald),
            title: Text(l.placeAllOf(places.govLabel(g.id, lang))),
            onTap: () => done(PlaceSel(governorateId: g.id)),
          ),
        );
      }
      for (final city in _sorted(places.citiesOf(_gov).where(state.choosable).toList(), lang)) {
        final hoods = places.hoodsOf(city.id).where(state.choosable);
        rows.add(
          ListTile(
            leading: Icon(_icon(PlaceKind.city), color: c.emerald),
            title: Text(city.label(lang)),
            selected: widget.current?.city == city.id,
            trailing: hoods.isEmpty ? null : const Icon(Icons.chevron_right_rounded),
            onTap: () =>
                hoods.isEmpty ? done(PlaceSel(governorateId: _gov, cityId: city.id)) : setState(() => _city = city.id),
          ),
        );
      }
    } else {
      final city = places.city(_city);
      if (city != null) {
        rows.add(
          ListTile(
            leading: Icon(Icons.select_all_rounded, color: c.emerald),
            title: Text(l.placeAllOf(city.label(lang))),
            onTap: () => done(PlaceSel(governorateId: _gov, cityId: city.id)),
          ),
        );
      }
      for (final h in _sorted(places.hoodsOf(_city).where(state.choosable).toList(), lang)) {
        rows.add(
          ListTile(
            leading: Icon(_icon(PlaceKind.hood), color: c.emerald),
            title: Text(h.label(lang)),
            selected: widget.current?.hood == h.id,
            onTap: () => done(PlaceSel(governorateId: _gov, cityId: _city, neighborhoodId: h.id)),
          ),
        );
      }
    }

    final crumb = _city != null
        ? places.city(_city)?.label(lang)
        : _gov != null
        ? places.govLabel(_gov, lang)
        : null;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
            child: Row(
              children: [
                if (crumb != null && q.isEmpty)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    icon: const BackButtonIcon(),
                    onPressed: () => setState(() => _city != null ? _city = null : _gov = null),
                  ),
                Expanded(
                  child: Text(
                    q.isEmpty && crumb != null ? crumb : l.placePickTitle,
                    style: context.text.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.placeSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _query.clear,
                      ),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Space.xl),
              children: rows,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(PlaceKind kind) => switch (kind) {
    PlaceKind.gov => Icons.map_outlined,
    PlaceKind.city => Icons.location_city_rounded,
    PlaceKind.hood => Icons.home_work_outlined,
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.xxs),
    child: Text(
      text.toUpperCase(),
      style: context.text.labelSmall?.copyWith(color: context.colors.inkMuted, letterSpacing: 1.1),
    ),
  );
}

/// "Near Abdoun · Amman" for a pin, from the nearest known place: what the
/// app can say about a point without a geocoding service.
String nearPlaceLabel(Places places, double lat, double lng, String lang, String Function(String) near) {
  final sel = places.nearest(lat, lng);
  final name = places.selLabel(sel, lang);
  return name.isEmpty ? '' : near(name);
}

/// Keeps [unawaited] imported for callers that fire the sheet and forget it.
void openPlacePicker(BuildContext context, ValueChanged<PlaceSel?> onPicked, {PlaceSel? current, String? anyLabel}) {
  unawaited(
    showPlacePicker(context, current: current, anyLabel: anyLabel).then((p) {
      if (p != null) onPicked(p.isEmpty ? null : p);
    }),
  );
}
