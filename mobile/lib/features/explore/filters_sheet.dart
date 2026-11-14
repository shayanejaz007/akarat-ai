import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/place_picker.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/listing_filters.dart';
import '../../shared/reference/market_data.dart';
import '../../shared/reference/places.dart';
import '../../shared/widgets/pickers.dart';

/// Edits a copy of the filters and returns it on "Show results".
Future<ListingFilters?> showFiltersSheet(BuildContext context, ListingFilters current) {
  return showModalBottomSheet<ListingFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FiltersSheet(initial: current),
  );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial});
  final ListingFilters initial;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late ListingFilters _f = widget.initial;
  late final _minPrice = TextEditingController(text: _f.minPrice?.toString() ?? '');
  late final _maxPrice = TextEditingController(text: _f.maxPrice?.toString() ?? '');
  late final _minArea = TextEditingController(text: _f.minArea?.toString() ?? '');
  late final _maxArea = TextEditingController(text: _f.maxArea?.toString() ?? '');

  @override
  void dispose() {
    for (final c in [_minPrice, _maxPrice, _minArea, _maxArea]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _n(TextEditingController c) {
    final digits = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  ListingFilters _result() => ListingFilters(
    deal: _f.deal,
    cityId: _f.cityId,
    neighborhoodId: _f.neighborhoodId,
    type: _f.type,
    minBeds: _f.minBeds,
    minBaths: _f.minBaths,
    minPrice: _n(_minPrice),
    maxPrice: _n(_maxPrice),
    minArea: _n(_minArea),
    maxArea: _n(_maxArea),
    availableOnly: _f.availableOnly,
    sort: _f.sort,
  );

  void _clear() {
    setState(() {
      _f = ListingFilters(deal: _f.deal, sort: _f.sort);
      for (final c in [_minPrice, _maxPrice, _minArea, _maxArea]) {
        c.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = context.lang;
    final c = context.colors;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.xs, Space.xs),
            child: Row(
              children: [
                Expanded(child: Text(l.exploreFilters, style: context.text.titleLarge)),
                TextButton(onPressed: _clear, child: Text(l.filterClearAll)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              // Room above the first field for its floating label.
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.lg),
              children: [
                // Any governorate, town or neighbourhood, by search or by level.
                PlaceField(
                  label: l.filterCity,
                  anyLabel: l.placeAnywhere,
                  value: _f.governorateId == null && _f.cityId == null
                      ? null
                      : PlaceSel(governorateId: _f.governorateId, cityId: _f.cityId, neighborhoodId: _f.neighborhoodId),
                  onChanged: (p) => setState(
                    () => _f = p == null
                        ? _f.copyWith(clearCity: true, clearNeighborhood: true)
                        : p.city == null
                        ? _f.copyWith(governorateId: p.gov, clearCity: true, clearNeighborhood: true)
                        : _f.copyWith(cityId: p.city, neighborhoodId: p.hood, clearNeighborhood: true),
                  ),
                ),
                const SizedBox(height: Space.lg),
                Text(l.filterType, style: context.text.titleSmall),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: [
                    ChoiceChip(
                      label: Text(l.filterAnyType),
                      selected: _f.type == null,
                      onSelected: (_) => setState(() => _f = _f.copyWith(clearType: true)),
                    ),
                    for (final t in Market.types)
                      ChoiceChip(
                        avatar: Icon(propertyTypeIcon(t.id), size: 18),
                        label: Text(t.label(lang)),
                        selected: _f.type == t.id,
                        onSelected: (_) => setState(() => _f = _f.copyWith(type: t.id)),
                      ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                _CountRow(
                  label: l.filterBeds,
                  anyLabel: l.filterAny,
                  max: 5,
                  value: _f.minBeds,
                  onChanged: (v) =>
                      setState(() => _f = v == null ? _f.copyWith(clearBeds: true) : _f.copyWith(minBeds: v)),
                ),
                const SizedBox(height: Space.md),
                _CountRow(
                  label: l.filterBaths,
                  anyLabel: l.filterAny,
                  max: 4,
                  value: _f.minBaths,
                  onChanged: (v) =>
                      setState(() => _f = v == null ? _f.copyWith(clearBaths: true) : _f.copyWith(minBaths: v)),
                ),
                const SizedBox(height: Space.lg),
                Text(l.filterPrice, style: context.text.titleSmall),
                const SizedBox(height: Space.xs),
                _RangeFields(min: _minPrice, max: _maxPrice, minLabel: l.filterMin, maxLabel: l.filterMax),
                const SizedBox(height: Space.lg),
                Text(l.filterSize, style: context.text.titleSmall),
                const SizedBox(height: Space.xs),
                _RangeFields(min: _minArea, max: _maxArea, minLabel: l.filterMin, maxLabel: l.filterMax),
                const SizedBox(height: Space.md),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.filterAvailableOnly),
                  value: _f.availableOnly,
                  onChanged: (v) => setState(() => _f = _f.copyWith(availableOnly: v)),
                ),
                const SizedBox(height: Space.sm),
                NoticeLine(icon: Icons.auto_awesome_outlined, text: l.filterAmenitiesNote, tone: c.emerald),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _result()),
                  child: Text(l.filterShowResults),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.anyLabel,
    required this.max,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String anyLabel;
  final int max;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.titleSmall),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            ChoiceChip(label: Text(anyLabel), selected: value == null, onSelected: (_) => onChanged(null)),
            for (var i = 1; i <= max; i++)
              ChoiceChip(label: Text('$i+'), selected: value == i, onSelected: (_) => onChanged(i)),
          ],
        ),
      ],
    );
  }
}

class _RangeFields extends StatelessWidget {
  const _RangeFields({required this.min, required this.max, required this.minLabel, required this.maxLabel});
  final TextEditingController min;
  final TextEditingController max;
  final String minLabel;
  final String maxLabel;

  @override
  Widget build(BuildContext context) {
    InputDecoration d(String label) => InputDecoration(labelText: label);
    const formatters = [WesternDigitsFormatter()];
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: min,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: d(minLabel),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: TextField(
            controller: max,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: d(maxLabel),
          ),
        ),
      ],
    );
  }
}
