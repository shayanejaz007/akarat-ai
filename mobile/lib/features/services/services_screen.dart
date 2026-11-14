import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/reference/places.dart';
import '../../shared/services/supabase_providers.dart';
import 'services_models.dart';
import 'services_ui.dart';

/// Services: what people can ask for (service_categories), a search over
/// it in both languages, and the way to My service requests. Reached from
/// Home and Profile; not a tab of its own.
class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Matches in either language, folded the way place names are, so
  /// "التكييف" and "تكييف" find the same thing.
  static bool _matches(ServiceCategory c, String q) {
    final qa = foldAr(q);
    final qe = foldEn(q);
    for (final t in [c.en, c.ar, c.examplesEn, c.examplesAr]) {
      if (t.isEmpty) continue;
      if (qa.isNotEmpty && foldAr(t).contains(qa)) return true;
      if (qe.isNotEmpty && foldEn(t).contains(qe)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final inset = Layout.inset(context);
    final cats = ref.watch(serviceCategoriesProvider);
    final open = ref.watch(myServiceRequestsProvider).value?.where((r) => r.open).length ?? 0;
    final q = _search.text.trim();

    void request([String? category]) =>
        unawaited(context.push(category == null ? Routes.serviceRequest : Routes.serviceRequestFor(category)));

    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          ref.invalidate(serviceCategoriesProvider);
          await ref.read(serviceCategoriesProvider.future).catchError((Object _) => const <ServiceCategory>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(
              title: l.servicesTitle,
              actions: [
                if (ref.watch(isSignedInProvider))
                  IconButton(
                    tooltip: l.servicesMine,
                    onPressed: () => unawaited(context.push(Routes.myServiceRequests)),
                    icon: Badge(
                      isLabelVisible: open > 0,
                      label: Text('$open'),
                      child: const Icon(Icons.receipt_long_outlined),
                    ),
                  ),
              ],
            ),
            SliverPadding(
              padding: inset.copyWith(top: 0, bottom: Space.md),
              sliver: SliverList.list(
                children: [
                  Text(l.servicesHeadline, style: context.text.headlineSmall),
                  const SizedBox(height: Space.xs),
                  Text(l.servicesIntro, style: context.text.bodyMedium?.copyWith(color: c.inkMuted, height: 1.5)),
                  const SizedBox(height: Space.md),
                  FilledButton.icon(
                    onPressed: () => request(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l.servicesRequest),
                  ),
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l.servicesSearch,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _search.clear,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            ...cats.when(
              skipLoadingOnReload: true,
              loading: () => [
                SliverPadding(
                  padding: inset,
                  sliver: const SliverToBoxAdapter(child: Skeleton(height: 320)),
                ),
              ],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: e is ServiceRefusal && e.code == 'not_set_up'
                      ? EmptyState(icon: Icons.handyman_outlined, title: l.servicesNotReady, compact: true)
                      : ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(serviceCategoriesProvider)),
                ),
              ],
              data: (all) {
                final shown = q.isEmpty ? all : all.where((x) => _matches(x, q)).toList();
                final custom = all.where((x) => x.custom).firstOrNull;
                if (shown.isEmpty) {
                  return [
                    SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.search_off_rounded,
                        title: l.servicesNoMatch(q),
                        body: l.servicesNoMatchBody,
                        compact: true,
                        action: custom == null
                            ? null
                            : FilledButton.tonal(onPressed: () => request(custom.id), child: Text(l.servicesCustomCta)),
                      ),
                    ),
                  ];
                }
                return [
                  SliverPadding(
                    padding: inset.copyWith(top: 0),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: Space.sm,
                        crossAxisSpacing: Space.sm,
                        mainAxisExtent: 150,
                      ),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _CategoryCard(category: shown[i], onTap: () => request(shown[i].id)),
                    ),
                  ),
                ];
              },
            ),
            SliverPadding(
              padding: inset.copyWith(top: Space.xl, bottom: Space.xxl),
              sliver: SliverList.list(
                children: [
                  Text(l.servicesHow, style: context.text.titleMedium),
                  const SizedBox(height: Space.sm),
                  for (final (i, (t, b)) in [
                    (l.servicesStep1, l.servicesStep1Body),
                    (l.servicesStep2, l.servicesStep2Body),
                    (l.servicesStep3, l.servicesStep3Body),
                  ].indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: c.emerald,
                            child: Text(
                              lang == 'ar' ? ['١', '٢', '٣'][i] : '${i + 1}',
                              style: context.text.labelMedium?.copyWith(color: c.onForest),
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t, style: context.text.titleSmall),
                                Text(b, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});
  final ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: c.border, style: category.custom ? BorderStyle.solid : BorderStyle.solid),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ServiceIconTile(icon: category.icon, size: 42),
                const SizedBox(height: Space.sm),
                Text(category.name(lang), style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.hair),
                Expanded(
                  child: Text(
                    category.examples(lang),
                    style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
