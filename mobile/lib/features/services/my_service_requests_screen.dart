import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/reference/places_provider.dart';
import 'services_models.dart';
import 'services_repository.dart';
import 'services_ui.dart';

/// Every service the signed-in person has asked for and where it stands,
/// with the team's notes as the team wrote them. A request can be cancelled
/// until work begins. Nothing here shows a price, a technician or a date
/// unless the team wrote one in a note.
class MyServiceRequestsScreen extends ConsumerWidget {
  const MyServiceRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final inset = Layout.inset(context);
    final async = ref.watch(myServiceRequestsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(context.push(Routes.serviceRequest)),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.servicesRequest),
      ),
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        onRefresh: () async {
          ref.invalidate(myServiceRequestsProvider);
          await ref.read(myServiceRequestsProvider.future).catchError((Object _) => const <ServiceRequest>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(title: l.servicesMine),
            SliverPadding(
              padding: inset.copyWith(top: 0, bottom: Space.sm),
              sliver: SliverToBoxAdapter(
                child: Text(l.svMineSub, style: context.text.bodySmall?.copyWith(color: context.colors.inkMuted)),
              ),
            ),
            ...async.when(
              skipLoadingOnReload: true,
              loading: () => [
                SliverPadding(
                  padding: inset,
                  sliver: const SliverToBoxAdapter(child: Skeleton(height: 240)),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: e is ServiceRefusal && e.code == 'not_set_up'
                      ? EmptyState(icon: Icons.handyman_outlined, title: l.servicesNotReady)
                      : ErrorState(error: e, onRetry: () => ref.invalidate(myServiceRequestsProvider)),
                ),
              ],
              data: (rows) => rows.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: l.svMineEmpty,
                          action: FilledButton(
                            onPressed: () => unawaited(context.push(Routes.services)),
                            child: Text(l.servicesTitle),
                          ),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: inset.copyWith(top: Space.xs, bottom: 96),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                          itemBuilder: (context, i) => _RequestCard(key: ValueKey(rows[i].id), r: rows[i]),
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({super.key, required this.r});
  final ServiceRequest r;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _open = false;
  Map<String, String> _urls = const {};

  Future<void> _toggle() async {
    setState(() => _open = !_open);
    if (_open && widget.r.photos.isNotEmpty && _urls.isEmpty) {
      final urls = await ref.read(servicesRepositoryProvider).photoUrls(widget.r.photos);
      if (mounted) setState(() => _urls = urls);
    }
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.svCancelAsk),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.svCancelBody),
            const SizedBox(height: Space.sm),
            TextField(
              controller: reason,
              maxLength: 500,
              decoration: InputDecoration(labelText: l.svCancelReason),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.svCancelNo)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.svCancelYes),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(servicesRepositoryProvider).cancel(widget.r.id, reason: text);
      messenger.showSnackBar(SnackBar(content: Text(l.svCancelled)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.svCancelFail)));
    }
    ref.invalidate(myServiceRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final r = widget.r;
    final places = ref.watch(placesNowProvider).places;
    final where = [
      places.placeLabel(r.cityId, r.neighborhoodId, lang),
      r.address,
    ].where((s) => s.isNotEmpty).join(lang == 'ar' ? '، ' : ', ');
    final note = r.teamNote;
    final step = r.step;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.card,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ServiceIconTile(icon: r.icon, size: 40),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title(lang), style: context.text.titleSmall),
                    Text(
                      r.ref,
                      textDirection: TextDirection.ltr,
                      style: context.text.labelSmall?.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
              ),
              ServiceStatusPill(status: r.status),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(serviceStatusBody(l, r.status), style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
          if (step >= 0) ...[
            const SizedBox(height: Space.sm),
            Semantics(
              label: serviceStatusLabel(l, r.status),
              excludeSemantics: true,
              child: Row(
                children: [
                  for (var i = 0; i < serviceFlow.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(color: i <= step ? c.emerald : c.border, borderRadius: Radii.chip),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.sm),
          Text(l.svSent(Fmt.date(r.createdAt, lang: lang)), style: context.text.bodySmall),
          Text(
            l.svPreferred('${Fmt.night(r.preferredDate, lang: lang)} · ${serviceWindowLabel(l, r.preferredWindow)}'),
            style: context.text.bodySmall,
          ),
          if (where.isNotEmpty) Text(where, style: context.text.bodySmall),
          if (note != null) ...[
            const SizedBox(height: Space.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(color: c.emerald.withValues(alpha: 0.07), borderRadius: Radii.field),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.svTeamNote,
                    style: context.text.labelSmall?.copyWith(color: c.emerald, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Space.hair),
                  UserText(note, style: context.text.bodyMedium),
                ],
              ),
            ),
          ],
          if (_open) ...[
            const Divider(height: Space.xl),
            UserText(r.description, style: context.text.bodyMedium),
            if (r.photos.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final p in r.photos)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: _urls[p] == null
                            ? ColoredBox(color: c.surfaceMuted)
                            : Image.network(
                                _urls[p]!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(color: c.surfaceMuted),
                              ),
                      ),
                    ),
                ],
              ),
            ],
            if (r.events.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Text(l.svUpdates, style: context.text.titleSmall),
              const SizedBox(height: Space.xs),
              for (final e in r.events.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle, size: 8, color: e.kind == 'note' ? c.inkMuted : c.emerald),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${e.kind == 'created'
                                  ? l.svEventCreated
                                  : e.kind == 'note'
                                  ? l.svEventNote
                                  : serviceStatusLabel(l, e.status ?? '')} · ${Fmt.date(e.at, lang: lang)}',
                              style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (e.note != null) ...[
                              Text(e.byCustomer ? l.svYourNote : l.svTeamNote, style: context.text.labelSmall),
                              UserText(e.note!, style: context.text.bodySmall),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const SizedBox(height: Space.xs),
          // Side by side, or one under the other when the text is large.
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => unawaited(_toggle()),
                icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: Text(l.svDetails),
              ),
              if (r.cancellable)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  onPressed: () => unawaited(_cancel()),
                  child: Text(l.svCancel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
