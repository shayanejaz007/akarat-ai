import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/layout.dart';
import '../../../core/widgets/listing_image.dart';
import '../../../core/widgets/maps.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/state_views.dart';
import '../../../shared/models/listing.dart';
import '../../../shared/reference/market_data.dart';
import '../../../shared/widgets/pickers.dart';
import '../application/listing_wizard_controller.dart';
import '../domain/listing_draft.dart';

/// What stops the reader leaving [step], or null. Only the steps holding a
/// required field can stop them; everything else is optional.
String? stepProblem(BuildContext context, WidgetRef ref, String? editId, int step) {
  final l = context.l10n;
  final d = ref.read(listingWizardProvider(editId)).draft;
  switch (step) {
    case 2:
      if (d.cityId == null) return l.listingMissingCity;
    case 3:
      final year = ListingDraft.number(d.yearBuilt);
      final max = DateTime.now().year + 5;
      if (year != null && (year < 1900 || year > max)) return l.validationYear(max);
    case 4:
      if ((ListingDraft.number(d.price) ?? 0) <= 0) return l.listingMissingPrice;
      if (d.contactPhone.trim().isNotEmpty && Phone.dialable(d.contactPhone) == null) return l.validationPhone;
    case 6:
      if (d.titleEn.trim().isEmpty && d.titleAr.trim().isEmpty) return l.listingMissingTitle;
  }
  return null;
}

/// A text field bound to one draft value. Owns its controller so typing
/// never rebuilds the field from state.
class DraftTextField extends StatefulWidget {
  const DraftTextField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.numeric = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.helper,
    this.keyboardType,
    this.textDirection,
    this.prefixIcon,
    this.suffixText,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final bool numeric;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final String? helper;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final IconData? prefixIcon;
  final String? suffixText;

  @override
  State<DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<DraftTextField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      textDirection: widget.textDirection,
      keyboardType: widget.keyboardType ?? (widget.numeric ? TextInputType.number : null),
      inputFormatters: widget.numeric ? const [WesternDigitsFormatter()] : null,
      textInputAction: widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 3,
        alignLabelWithHint: widget.maxLines > 1,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixText: widget.suffixText,
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.title, required this.selected, required this.onTap, this.body});
  final IconData icon;
  final String title;
  final String? body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        borderRadius: Radii.field,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          padding: const EdgeInsets.all(Space.md),
          // Soft grey until chosen, like the rest of the app; the edge is
          // always there, clear until chosen, so nothing shifts.
          decoration: BoxDecoration(
            color: selected ? Color.alphaBlend(c.emerald.withValues(alpha: 0.1), c.surface) : c.surfaceMuted,
            borderRadius: Radii.field,
            border: Border.all(color: selected ? c.emerald : Colors.transparent, width: 1.6),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.surface, borderRadius: Radii.tile),
                child: Icon(icon, color: selected ? c.forest : c.inkMuted, size: 24),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall),
                    if (body != null) Text(body!, style: context.text.bodySmall),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, color: c.emerald),
            ],
          ),
        ),
      ),
    );
  }
}

class PurposeStep extends ConsumerWidget {
  const PurposeStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final d = ref.watch(listingWizardProvider(editId).select((s) => s.draft.deal));
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    return Column(
      children: [
        _ChoiceCard(
          icon: Icons.sell_outlined,
          title: l.purposeSale,
          body: l.purposeSaleBody,
          selected: d == DealType.sale,
          onTap: () => ctrl.update((x) => x.copyWith(deal: DealType.sale)),
        ),
        const SizedBox(height: Space.sm),
        _ChoiceCard(
          icon: Icons.key_outlined,
          title: l.purposeRent,
          body: l.purposeRentBody,
          selected: d == DealType.rent,
          onTap: () => ctrl.update((x) => x.copyWith(deal: DealType.rent)),
        ),
      ],
    );
  }
}

class TypeStep extends ConsumerWidget {
  const TypeStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(listingWizardProvider(editId).select((s) => s.draft.propertyType));
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    final lang = context.lang;
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth > 500 ? 3 : 2;
        final w = (box.maxWidth - (cols - 1) * Space.sm) / cols;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final t in Market.types)
              SizedBox(
                width: w,
                child: Semantics(
                  selected: type == t.id,
                  button: true,
                  child: Pressable(
                    onTap: () => ctrl.update((x) => x.copyWith(propertyType: t.id)),
                    borderRadius: Radii.field,
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      height: 100,
                      decoration: BoxDecoration(
                        color: type == t.id
                            ? Color.alphaBlend(c.emerald.withValues(alpha: 0.1), c.surface)
                            : c.surfaceMuted,
                        borderRadius: Radii.field,
                        border: Border.all(color: type == t.id ? c.emerald : Colors.transparent, width: 1.6),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.surface, borderRadius: Radii.tile),
                            child: Icon(propertyTypeIcon(t.id), color: type == t.id ? c.forest : c.inkMuted, size: 24),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(t.label(lang), style: context.text.labelLarge),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class LocationStep extends ConsumerWidget {
  const LocationStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final d = ref.watch(listingWizardProvider(editId).select((s) => s.draft));
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    final hoods = Market.neighborhoodsOf(d.cityId);
    final city = Market.city(d.cityId);

    Widget picker(String label, String value, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: Radii.field,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.expand_more_rounded)),
        child: Text(value, style: context.text.bodyLarge),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        picker(l.fieldCity, city?.label(lang) ?? '—', () async {
          final id = await showChoiceSheet(
            context: context,
            title: l.fieldCity,
            options: Market.cities,
            selected: d.cityId,
          );
          if (id != null && id.isNotEmpty && id != d.cityId) {
            ctrl.update((x) => x.copyWith(cityId: id, clearNeighborhood: true));
          }
        }),
        const SizedBox(height: Space.sm),
        picker(
          l.fieldNeighborhood,
          Market.neighborhood(d.neighborhoodId)?.label(lang) ?? l.fieldNeighborhoodNone,
          () async {
            final id = await showChoiceSheet(
              context: context,
              title: l.fieldNeighborhood,
              options: hoods,
              selected: d.neighborhoodId,
              anyLabel: l.fieldNeighborhoodNone,
            );
            if (id == null) return;
            ctrl.update((x) => id.isEmpty ? x.copyWith(clearNeighborhood: true) : x.copyWith(neighborhoodId: id));
          },
        ),
        const SizedBox(height: Space.xl),
        Text(l.locationPinTitle, style: context.text.titleMedium),
        const SizedBox(height: Space.xxs),
        ...[
          Text(l.locationPinBody, style: context.text.bodySmall),
          const SizedBox(height: Space.sm),
          ClipRRect(
            borderRadius: Radii.card,
            child: SizedBox(
              height: 260,
              child: PinPicker(
                initial: d.hasPin ? LatLngPoint(d.lat!, d.lng!) : null,
                center: city == null ? Geo.jordanCenter : LatLngPoint(city.lat, city.lng),
                onChanged: ctrl.setPin,
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Icon(
                d.hasPin ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 18,
                color: d.hasPin ? c.emerald : c.inkFaint,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  d.hasPin ? '${d.lat!.toStringAsFixed(5)}, ${d.lng!.toStringAsFixed(5)}' : l.locationPinNone,
                  textDirection: TextDirection.ltr,
                  style: context.text.bodySmall,
                ),
              ),
              if (d.hasPin)
                TextButton(
                  onPressed: () => ctrl.update((x) => x.copyWith(clearPin: true)),
                  child: Text(l.locationPinRemove),
                ),
            ],
          ),
        ],
        if (d.hasPin) ...[
          const SizedBox(height: Space.lg),
          Text(l.precisionTitle, style: context.text.titleMedium),
          const SizedBox(height: Space.sm),
          _ChoiceCard(
            icon: Icons.blur_circular_rounded,
            title: l.precisionApprox,
            body: l.precisionApproxNote,
            selected: d.precision == LocationPrecision.approximate,
            onTap: () => ctrl.update((x) => x.copyWith(precision: LocationPrecision.approximate)),
          ),
          const SizedBox(height: Space.sm),
          _ChoiceCard(
            icon: Icons.push_pin_outlined,
            title: l.precisionExact,
            body: l.precisionExactNote,
            selected: d.precision == LocationPrecision.exact,
            onTap: () => ctrl.update((x) => x.copyWith(precision: LocationPrecision.exact)),
          ),
          const SizedBox(height: Space.md),
          DraftTextField(
            value: d.address,
            label: l.fieldAddress,
            helper: l.fieldAddressHelp,
            maxLength: 200,
            prefixIcon: Icons.signpost_outlined,
            onChanged: (v) => ctrl.update((x) => x.copyWith(address: v)),
          ),
        ],
      ],
    );
  }
}

class DetailsStep extends ConsumerWidget {
  const DetailsStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final provider = listingWizardProvider(editId);
    final d = ref.read(provider).draft;
    final beds = ref.watch(provider.select((s) => ListingDraft.number(s.draft.bedrooms)?.toInt()));
    final baths = ref.watch(provider.select((s) => ListingDraft.number(s.draft.bathrooms)?.toInt()));
    final ctrl = ref.read(provider.notifier);
    final land = d.propertyType == 'land' || d.propertyType == 'farm';
    final sqm = context.isArabic ? 'م²' : 'm²';
    return Column(
      children: [
        // Counts are picked, not typed: no keyboard, no stray characters.
        if (!land) ...[
          GroupedSection(
            children: [
              _CountRow(
                icon: Icons.bed_outlined,
                label: l.fieldBedrooms,
                value: beds,
                onStep: (by) => ctrl.update((x) => x.copyWith(bedrooms: _CountRow.step(x.bedrooms, by))),
              ),
              _CountRow(
                icon: Icons.bathtub_outlined,
                label: l.fieldBathrooms,
                value: baths,
                onStep: (by) => ctrl.update((x) => x.copyWith(bathrooms: _CountRow.step(x.bathrooms, by))),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
        ],
        DraftTextField(
          value: d.areaSqm,
          label: l.fieldAreaSqm,
          numeric: true,
          prefixIcon: Icons.square_foot_rounded,
          suffixText: sqm,
          onChanged: (v) => ctrl.update((x) => x.copyWith(areaSqm: v)),
        ),
        const SizedBox(height: Space.sm),
        DraftTextField(
          value: d.landSqm,
          label: l.fieldLandSqm,
          numeric: true,
          prefixIcon: Icons.landscape_outlined,
          suffixText: sqm,
          onChanged: (v) => ctrl.update((x) => x.copyWith(landSqm: v)),
        ),
        if (!land) ...[
          const SizedBox(height: Space.sm),
          DraftTextField(
            value: d.yearBuilt,
            label: l.fieldYearBuilt,
            numeric: true,
            prefixIcon: Icons.event_outlined,
            onChanged: (v) => ctrl.update((x) => x.copyWith(yearBuilt: v)),
          ),
        ],
      ],
    );
  }
}

/// A count with minus and plus. Below zero it reads "not given", so a field
/// left alone is never saved as a number the owner did not choose.
class _CountRow extends StatelessWidget {
  const _CountRow({required this.icon, required this.label, required this.value, required this.onStep});
  final IconData icon;
  final String label;
  final int? value;

  /// Called with +1 or -1; the owner applies it to the current draft.
  final ValueChanged<int> onStep;

  static const _max = 20;

  /// The draft's text after one step: up from "not given" is 1, down from
  /// 0 is "not given" again, and nothing goes past [_max].
  static String step(String current, int by) {
    final v = ListingDraft.number(current)?.toInt();
    final next = v == null ? (by > 0 ? 1 : null) : (v + by < 0 ? null : (v + by).clamp(0, _max));
    return next == null ? '' : '$next';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final v = value;
    void dec() => onStep(-1);
    void inc() => onStep(1);
    Widget round(IconData glyph, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap == null
          ? null
          : () {
              unawaited(HapticFeedback.selectionClick());
              onTap();
            },
      style: IconButton.styleFrom(
        side: BorderSide(color: onTap == null ? c.border.withValues(alpha: 0.6) : c.border),
        foregroundColor: c.forest,
        disabledForegroundColor: c.inkFaint,
      ),
      icon: Icon(glyph, size: 20),
    );
    return Semantics(
      label: label,
      value: v == null ? '—' : '$v',
      increasedValue: v == null ? '1' : '${(v + 1).clamp(0, _max)}',
      decreasedValue: v == null || v == 0 ? '—' : '${v - 1}',
      onIncrease: v != null && v >= _max ? null : inc,
      onDecrease: v == null ? null : dec,
      child: GroupedTile(
        icon: icon,
        title: label,
        trailing: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              round(Icons.remove_rounded, l.a11yDecrease, v == null ? null : dec),
              SizedBox(
                width: 40,
                child: Text(
                  v == null ? '—' : '$v',
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(color: v == null ? c.inkFaint : c.ink),
                ),
              ),
              round(Icons.add_rounded, l.a11yIncrease, v != null && v >= _max ? null : inc),
            ],
          ),
        ),
      ),
    );
  }
}

class PriceStep extends ConsumerWidget {
  const PriceStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final d = ref.read(listingWizardProvider(editId)).draft;
    final rent = ref.watch(listingWizardProvider(editId).select((s) => s.draft.deal == DealType.rent));
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    return Column(
      children: [
        DraftTextField(
          value: d.price,
          label: rent ? l.fieldPriceRent : l.fieldPrice,
          numeric: true,
          prefixIcon: Icons.payments_outlined,
          onChanged: (v) => ctrl.update((x) => x.copyWith(price: v)),
        ),
        const SizedBox(height: Space.lg),
        DraftTextField(
          value: d.contactPhone,
          label: l.fieldContactPhone,
          helper: l.fieldContactPhoneHelp,
          keyboardType: TextInputType.phone,
          maxLength: 24,
          textDirection: TextDirection.ltr,
          prefixIcon: Icons.call_outlined,
          onChanged: (v) => ctrl.update((x) => x.copyWith(contactPhone: v)),
        ),
      ],
    );
  }
}

class AmenitiesStep extends ConsumerWidget {
  const AmenitiesStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(listingWizardProvider(editId).select((s) => s.draft.amenities));
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    final lang = context.lang;
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        for (final a in Market.amenities)
          FilterChip(
            avatar: Icon(amenityIcon(a.id), size: 18),
            label: Text(a.label(lang)),
            selected: selected.contains(a.id),
            showCheckmark: false,
            onSelected: (on) => ctrl.update(
              (x) => x.copyWith(amenities: on ? [...x.amenities, a.id] : x.amenities.where((y) => y != a.id).toList()),
            ),
          ),
      ],
    );
  }
}

class DescriptionStep extends ConsumerWidget {
  const DescriptionStep({super.key, required this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final d = ref.read(listingWizardProvider(editId)).draft;
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.fieldTitleHelp, style: context.text.bodySmall),
        const SizedBox(height: Space.md),
        DraftTextField(
          value: d.titleAr,
          label: l.fieldTitleAr,
          maxLength: 140,
          textDirection: TextDirection.rtl,
          onChanged: (v) => ctrl.update((x) => x.copyWith(titleAr: v)),
        ),
        const SizedBox(height: Space.sm),
        DraftTextField(
          value: d.titleEn,
          label: l.fieldTitleEn,
          maxLength: 140,
          textDirection: TextDirection.ltr,
          onChanged: (v) => ctrl.update((x) => x.copyWith(titleEn: v)),
        ),
        const SizedBox(height: Space.md),
        DraftTextField(
          value: d.descriptionAr,
          label: l.fieldDescAr,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          textDirection: TextDirection.rtl,
          onChanged: (v) => ctrl.update((x) => x.copyWith(descriptionAr: v)),
        ),
        const SizedBox(height: Space.sm),
        DraftTextField(
          value: d.descriptionEn,
          label: l.fieldDescEn,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          textDirection: TextDirection.ltr,
          onChanged: (v) => ctrl.update((x) => x.copyWith(descriptionEn: v)),
        ),
      ],
    );
  }
}

class PreviewStep extends ConsumerWidget {
  const PreviewStep({super.key, required this.editId});
  final String? editId;

  String _errorText(BuildContext context, Object error) {
    final l = context.l10n;
    final f = AppFailure.from(error);
    return switch (f.kind) {
      FailureKind.unknownArea => l.errorUnknownArea,
      FailureKind.storageMissing => l.errorStorageMissing,
      FailureKind.schemaMissing when (f.detail ?? '').contains('location') => l.errorGeoColumns,
      FailureKind.network || FailureKind.timeout => l.mediaUploadFailed,
      _ => context.failureMessage(error),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final s = ref.watch(listingWizardProvider(editId));
    final ctrl = ref.read(listingWizardProvider(editId).notifier);
    final d = s.draft;
    final problems = ctrl.problems();
    final cover = d.media.where((m) => !m.isVideo).firstOrNull;
    final title = (lang == 'ar' ? d.titleAr : d.titleEn).trim().isNotEmpty
        ? (lang == 'ar' ? d.titleAr : d.titleEn)
        : (d.titleAr.isNotEmpty ? d.titleAr : d.titleEn);
    final price = ListingDraft.number(d.price);

    Future<void> save({required bool publish}) async {
      final router = GoRouter.of(context);
      final saved = await ctrl.save(publish: publish);
      if (saved == null || !context.mounted) return;
      // On the root overlay, so it stays through the move to the dashboard.
      showSuccess(context, s.editing ? l.editSuccess : (publish ? l.publishSuccess : l.draftSuccess));
      if (s.editing) {
        router.pop();
      } else {
        unawaited(router.pushReplacement(Routes.dashboard));
      }
    }

    String problemText(DraftProblem p) => switch (p) {
      DraftProblem.title => l.listingMissingTitle,
      DraftProblem.price => l.listingMissingPrice,
      DraftProblem.city => l.listingMissingCity,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: cover == null
                    ? const ListingImage(url: null)
                    : cover.isLocal && cover.uploaded == null
                    ? Image.file(File(cover.localPath!), fit: BoxFit.cover, cacheWidth: 900)
                    : ListingImage(url: cover.stored!.url),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      price == null ? '—' : Fmt.price(price, lang: lang, rent: d.deal == DealType.rent),
                      style: context.type.price,
                    ),
                    const SizedBox(height: Space.hair),
                    Text(title.isEmpty ? '—' : title, style: context.text.titleSmall),
                    const SizedBox(height: Space.hair),
                    Text(
                      [
                        Market.type(d.propertyType)?.label(lang),
                        Market.placeLabel(d.cityId, d.neighborhoodId, lang),
                      ].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      [
                        if (d.bedrooms.isNotEmpty) '${l.specBeds}: ${d.bedrooms}',
                        if (d.bathrooms.isNotEmpty) '${l.specBaths}: ${d.bathrooms}',
                        if (d.areaSqm.isNotEmpty) Fmt.area(ListingDraft.number(d.areaSqm) ?? 0, lang: lang),
                        l.previewMediaCount(d.media.length),
                      ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                    if (d.hasPin) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        d.precision == LocationPrecision.exact ? l.precisionExact : l.precisionApprox,
                        style: context.text.labelMedium?.copyWith(color: c.emerald),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        for (final p in problems) ...[
          NoticeLine(icon: Icons.error_outline_rounded, text: problemText(p), tone: c.danger),
          const SizedBox(height: Space.xs),
        ],
        if (s.error != null) ...[
          Semantics(
            liveRegion: true,
            child: NoticeLine(icon: Icons.error_outline_rounded, text: _errorText(context, s.error!), tone: c.danger),
          ),
          const SizedBox(height: Space.sm),
        ],
        if (s.saving && s.uploadTotal > 0) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  l.mediaUploading(s.uploadDone.clamp(0, s.uploadTotal), s.uploadTotal),
                  style: context.text.bodySmall,
                ),
              ),
              Text(
                '${(100 * s.uploadDone.clamp(0, s.uploadTotal) / s.uploadTotal).round()}%',
                style: context.type.pill.copyWith(color: c.emerald),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: Radii.chip,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: s.uploadDone.clamp(0, s.uploadTotal) / s.uploadTotal),
              duration: Motion.of(context, Motion.slow),
              curve: Motion.standard,
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: c.emerald),
            ),
          ),
          const SizedBox(height: Space.md),
        ],
        if (s.editing)
          BusyButton(
            label: l.previewSaveChanges,
            busyLabel: l.previewWorking,
            icon: Icons.check_rounded,
            onPressed: problems.isEmpty ? () => save(publish: true) : null,
          )
        else ...[
          BusyButton(
            label: l.previewPublish,
            busyLabel: l.previewWorking,
            icon: Icons.publish_rounded,
            onPressed: problems.isEmpty && !s.saving ? () => save(publish: true) : null,
          ),
          const SizedBox(height: Space.sm),
          BusyButton(
            label: l.previewSaveDraft,
            style: BusyButtonStyle.outlined,
            onPressed: problems.isEmpty && !s.saving ? () => save(publish: false) : null,
          ),
          const SizedBox(height: Space.sm),
          Text(l.previewDraftNote, style: context.text.bodySmall),
        ],
      ],
    );
  }
}
