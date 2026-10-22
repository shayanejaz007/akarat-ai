import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../reference/market_data.dart';

/// Icons for property types, used on Home, filters and the listing form.
IconData propertyTypeIcon(String id) => switch (id) {
  'apartment' => Icons.apartment_rounded,
  'villa' => Icons.villa_outlined,
  'house' => Icons.house_outlined,
  'land' => Icons.landscape_outlined,
  'office' => Icons.business_center_outlined,
  'shop' => Icons.storefront_outlined,
  'building' => Icons.domain_rounded,
  'chalet' => Icons.cottage_outlined,
  'warehouse' => Icons.warehouse_outlined,
  'farm' => Icons.agriculture_outlined,
  _ => Icons.home_work_outlined,
};

IconData amenityIcon(String id) => switch (id) {
  'garden' => Icons.yard_outlined,
  'pool' => Icons.pool_rounded,
  'parking' => Icons.local_parking_rounded,
  'balcony' => Icons.balcony_outlined,
  'elevator' => Icons.elevator_outlined,
  'furnished' => Icons.chair_outlined,
  'security' => Icons.security_rounded,
  'heating' => Icons.local_fire_department_outlined,
  'ac' => Icons.ac_unit_rounded,
  'solar' => Icons.solar_power_outlined,
  'storage' => Icons.inventory_2_outlined,
  'smart' => Icons.smart_toy_outlined,
  'seaview' => Icons.water_rounded,
  'roof' => Icons.roofing_rounded,
  _ => Icons.check_circle_outline_rounded,
};

/// A searchable list in a bottom sheet. Returns the chosen id, or
/// [clearValue] for the "any" row, or null when dismissed.
Future<String?> showChoiceSheet({
  required BuildContext context,
  required String title,
  required List<Bilingual> options,
  String? selected,
  String? anyLabel,
  String clearValue = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _ChoiceSheet(title: title, options: options, selected: selected, anyLabel: anyLabel, clearValue: clearValue),
  );
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    this.selected,
    this.anyLabel,
    required this.clearValue,
  });
  final String title;
  final List<Bilingual> options;
  final String? selected;
  final String? anyLabel;
  final String clearValue;

  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final c = context.colors;
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.options
        : widget.options.where((o) => o.en.toLowerCase().contains(q) || o.ar.contains(_q.trim())).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: Row(
              children: [Expanded(child: Text(widget.title, style: context.text.titleLarge))],
            ),
          ),
          if (widget.options.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), isDense: true),
                textInputAction: TextInputAction.search,
              ),
            ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                if (widget.anyLabel != null && q.isEmpty)
                  _row(
                    context,
                    widget.anyLabel!,
                    null,
                    widget.selected == null || widget.selected!.isEmpty,
                    () => Navigator.pop(context, widget.clearValue),
                  ),
                for (final o in shown)
                  _row(
                    context,
                    o.label(lang),
                    lang == 'ar' ? o.en : o.ar,
                    o.id == widget.selected,
                    () => Navigator.pop(context, o.id),
                  ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Text(
                      '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String title, String? subtitle, bool selected, VoidCallback onTap) {
    final c = context.colors;
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected ? Icon(Icons.check_rounded, color: c.emerald) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
