import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/search_constraints.dart';
import '../../../shared/reference/market_data.dart';

/// One readable chip per constraint, each with the brief it leaves behind
/// when removed. The website shows the same brief and lets it be edited.
class ConstraintChip {
  const ConstraintChip(this.icon, this.label, this.without);
  final IconData icon;
  final String label;
  final SearchConstraints without;
}

List<ConstraintChip> constraintChips(BuildContext context, SearchConstraints c) {
  final l = context.l10n;
  final lang = context.lang;
  String money(int v) => Fmt.price(v, lang: lang, rent: c.deal == 'rent');
  return [
    if (c.deal != null)
      ConstraintChip(
        c.deal == 'rent' ? Icons.key_outlined : Icons.sell_outlined,
        c.deal == 'rent' ? l.dealRent : l.dealSale,
        c.copyWith(clearDeal: true),
      ),
    if (c.hood != null)
      ConstraintChip(
        Icons.place_outlined,
        Market.neighborhood(c.hood)?.label(lang) ?? c.hood!,
        c.copyWith(clearHood: true),
      ),
    if (c.city != null)
      ConstraintChip(
        Icons.location_city_outlined,
        Market.city(c.city)?.label(lang) ?? c.city!,
        c.copyWith(clearCity: true, clearHood: true),
      ),
    if (c.type != null)
      ConstraintChip(
        Icons.home_work_outlined,
        Market.type(c.type)?.label(lang) ?? c.type!,
        c.copyWith(clearType: true),
      ),
    if (c.beds != null) ConstraintChip(Icons.bed_outlined, l.chipBedsMin(c.beds!), c.copyWith(clearBeds: true)),
    if (c.baths != null) ConstraintChip(Icons.bathtub_outlined, l.chipBathsMin(c.baths!), c.copyWith(clearBaths: true)),
    if (c.budgetMin != null)
      ConstraintChip(Icons.trending_up_rounded, l.chipBudgetMin(money(c.budgetMin!)), c.copyWith(clearBudgetMin: true)),
    if (c.budgetMax != null)
      ConstraintChip(Icons.payments_outlined, l.chipBudgetMax(money(c.budgetMax!)), c.copyWith(clearBudgetMax: true)),
    if (c.areaMin != null)
      ConstraintChip(Icons.square_foot_rounded, l.chipAreaMin(Fmt.number(c.areaMin!)), c.copyWith(clearAreaMin: true)),
    for (final a in c.amenities)
      ConstraintChip(
        Icons.check_rounded,
        Market.amenity(a)?.label(lang) ?? a,
        c.copyWith(amenities: c.amenities.where((x) => x != a).toList()),
      ),
    if (c.internalOnly) ConstraintChip(Icons.verified_outlined, l.chipOnlyAkarat, c.copyWith(internalOnly: false)),
  ];
}
