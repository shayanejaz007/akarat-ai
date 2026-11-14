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
                  Text(l.servicesIntro, style: context.text.bodyLarge?.copyWith(color: c.inkMuted, height: 1.5)),
                  const SizedBox(height: Space.lg),
                  FilledButton(onPressed: () => request(), child: Text(l.servicesRequest)),
                  const SizedBox(height: Space.xl),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(l.servicesAll, style: context.text.titleLarge),
                      const SizedBox(width: Space.xs),
                      if (cats.value case final all?)
                        Text(
                          q.isEmpty ? '${all.length}' : '${all.where((x) => _matches(x, q)).length} / ${all.length}',
                          style: context.text.bodySmall?.copyWith(
                            color: c.inkMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
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
                // A ruled directory, each service keeping its number through
                // a search.
                return [
                  SliverPadding(
                    padding: inset.copyWith(top: 0, bottom: 0),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _CategoryRow(
                        number: all.indexOf(shown[i]) + 1,
                        category: shown[i],
                        first: i == 0,
                        onTap: () => request(shown[i].id),
                      ),
                    ),
                  ),
                ];
              },
            ),
            SliverPadding(
              padding: inset.copyWith(top: Space.xl, bottom: Space.xxl),
              sliver: SliverList.list(
                children: [
                  Text(l.servicesHow, style: context.text.titleLarge),
                  const SizedBox(height: Space.xs),
                  for (final (i, (t, b)) in [
                    (l.servicesStep1, l.servicesStep1Body),
                    (l.servicesStep2, l.servicesStep2Body),
                    (l.servicesStep3, l.servicesStep3Body),
                  ].indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 36,
                            child: Padding(
                              padding: const EdgeInsets.only(top: Space.hair),
                              child: ServiceNumeral(i + 1),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t, style: context.text.titleSmall),
                                const SizedBox(height: Space.hair),
                                Text(b, style: context.text.bodySmall?.copyWith(color: c.inkMuted, height: 1.45)),
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

/// One line of the directory: its number, icon, name and examples, ruled
/// off from the next. The whole line is the button.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.number, required this.category, required this.first, required this.onTap});
  final int number;
  final ServiceCategory category;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lang = context.lang;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          decoration: BoxDecoration(
            border: Border(
              top: first ? BorderSide(color: c.ink) : BorderSide.none,
              bottom: BorderSide(color: c.border),
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 30, child: ServiceNumeral(number, muted: true)),
              Icon(serviceIcon(category.icon), size: 22, color: c.ink),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.name(lang),
                      style: context.text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (category.examples(lang).isNotEmpty)
                      Text(
                        category.examples(lang),
                        style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(Icons.adaptive.arrow_forward_rounded, size: 18, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
