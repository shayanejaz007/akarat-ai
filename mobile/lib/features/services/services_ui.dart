import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/gen/app_localizations.dart';
import '../../app/theme/tokens.dart';
import '../../shared/services/supabase_providers.dart';
import 'services_models.dart';
import 'services_repository.dart';

/// The categories that are switched on. Read from the database, so an
/// admin's change shows in the app without a release.
final serviceCategoriesProvider = FutureProvider<List<ServiceCategory>>(
  (ref) => ref.watch(servicesRepositoryProvider).categories(),
);

/// The signed-in person's requests. Empty when signed out.
final myServiceRequestsProvider = FutureProvider<List<ServiceRequest>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(servicesRepositoryProvider).mine();
});

/// The same icons the website draws for a category's `icon`
/// (lib/service-icons.js), in Material's set. An unknown one is a toolbox.
IconData serviceIcon(String name) => switch (name) {
  'plumbing' => Icons.plumbing_rounded,
  'bathroom' => Icons.bathtub_outlined,
  'electrical' => Icons.electrical_services_rounded,
  'ac' => Icons.ac_unit_rounded,
  'painting' => Icons.format_paint_outlined,
  'carpentry' => Icons.carpenter_rounded,
  'cleaning' => Icons.cleaning_services_outlined,
  'appliance' => Icons.local_laundry_service_outlined,
  'water' => Icons.water_drop_outlined,
  'renovation' => Icons.construction_rounded,
  'pest' => Icons.pest_control_outlined,
  'moving' => Icons.local_shipping_outlined,
  'custom' => Icons.add_circle_outline_rounded,
  _ => Icons.handyman_outlined,
};

/// A status in the customer's words.
String serviceStatusLabel(AppLocalizations l, String status) => switch (status) {
  'pending' => l.svStatusPending,
  'under_review' => l.svStatusUnderReview,
  'accepted' => l.svStatusAccepted,
  'in_progress' => l.svStatusInProgress,
  'completed' => l.svStatusCompleted,
  'rejected' => l.svStatusRejected,
  'cancelled' => l.svStatusCancelled,
  _ => status,
};

/// What a status means for the customer, one line.
String serviceStatusBody(AppLocalizations l, String status) => switch (status) {
  'pending' => l.svBodyPending,
  'under_review' => l.svBodyUnderReview,
  'accepted' => l.svBodyAccepted,
  'in_progress' => l.svBodyInProgress,
  'completed' => l.svBodyCompleted,
  'rejected' => l.svBodyRejected,
  'cancelled' => l.svBodyCancelled,
  _ => '',
};

String serviceWindowLabel(AppLocalizations l, String w) => switch (w) {
  'morning' => l.svWindowMorning,
  'afternoon' => l.svWindowAfternoon,
  'evening' => l.svWindowEvening,
  _ => l.svWindowAny,
};

/// The status as a small pill, its colour always with its words.
class ServiceStatusPill extends StatelessWidget {
  const ServiceStatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final (bg, fg) = switch (status) {
      'completed' => (c.emerald, c.onForest),
      'accepted' || 'in_progress' || 'under_review' => (c.emerald.withValues(alpha: 0.12), c.emerald),
      'pending' => (c.gold.withValues(alpha: 0.16), c.ink),
      'rejected' => (c.danger.withValues(alpha: 0.12), c.danger),
      _ => (c.surfaceMuted, c.inkMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.chip),
      child: Text(
        serviceStatusLabel(l, status),
        style: context.text.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A category's icon in its rounded tile.
class ServiceIconTile extends StatelessWidget {
  const ServiceIconTile({super.key, required this.icon, this.size = 46});
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.emerald.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(serviceIcon(icon), color: c.emerald, size: size * 0.5),
    );
  }
}
