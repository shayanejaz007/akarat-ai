import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/widgets/layout.dart';
import '../../../core/widgets/state_views.dart';
import '../../tour/tour.dart';
import '../application/listing_wizard_controller.dart';
import 'media_step.dart';
import 'steps.dart';

/// The guided listing flow: purpose, type, location, details, price and
/// contact, features, description, media, review. New listings are kept on
/// the device as they are typed.
class ListingWizardScreen extends ConsumerWidget {
  const ListingWizardScreen({super.key, this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = listingWizardProvider(editId);
    final s = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final l = context.l10n;
    final c = context.colors;

    if (s.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l.listingEditTitle)),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (editId != null && s.original == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.listingEditTitle)),
        body: Center(
          child: ErrorState(error: s.error ?? Exception(), onRetry: () => ref.invalidate(provider)),
        ),
      );
    }

    final titles = [
      l.stepPurpose,
      l.stepType,
      l.stepLocation,
      l.stepDetails,
      l.stepPrice,
      l.stepAmenities,
      l.stepDescription,
      l.stepMedia,
      l.stepPreview,
    ];
    final step = s.step;
    final last = step == ListingWizardController.stepCount - 1;
    final targets = ref.watch(tourTargetsProvider);
    // Anchors only on the first step: the steps cross-fade, and a key may be
    // in the tree once.
    Key? anchor(GlobalKey k) => step == 0 ? k : null;

    // A new listing is already kept on the device, so leaving loses nothing;
    // an edit has no local copy, so unsaved changes would be lost.
    Future<bool> confirmLeave() async {
      if (!s.editing && !s.draft.isDirty) return true;
      return confirmAction(
        context,
        title: l.listingLeaveTitle,
        body: s.editing ? l.listingLeaveEditBody : l.listingLeaveBody,
        confirmLabel: l.listingLeaveGo,
        cancelLabel: l.listingLeaveStay,
        destructive: s.editing,
      );
    }

    Future<void> back() async {
      if (step > 0) {
        ctrl.goTo(step - 1);
        return;
      }
      if (await confirmLeave() && context.mounted) {
        context.canPop() ? context.pop() : context.go(Routes.profile);
      }
    }

    final screen = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !s.saving) unawaited(back());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: targets.wizardClose,
            tooltip: l.actionClose,
            icon: const Icon(Icons.close_rounded),
            onPressed: s.saving
                ? null
                : () async {
                    if (await confirmLeave() && context.mounted) {
                      context.canPop() ? context.pop() : context.go(Routes.profile);
                    }
                  },
          ),
          title: Text(s.editing ? l.listingEditTitle : l.listingNewTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (step + 1) / ListingWizardController.stepCount),
              duration: Motion.of(context, Motion.normal),
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 4),
            ),
          ),
        ),
        body: Column(
          children: [
            if (s.restored && step == 0)
              Padding(
                padding: Layout.inset(context, top: Space.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: NoticeLine(icon: Icons.restore_rounded, text: l.listingDraftRestored, tone: c.emerald),
                    ),
                    TextButton(onPressed: ctrl.discardDraft, child: Text(l.listingDraftDiscard)),
                  ],
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.normal),
                switchInCurve: Motion.standard,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: ListView(
                  key: ValueKey('step-$step-${s.restored}'),
                  padding: Layout.inset(context, top: Space.md, bottom: Space.xxl),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    Column(
                      key: anchor(targets.wizardProgress),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.stepOf(step + 1, ListingWizardController.stepCount),
                          style: context.text.labelMedium?.copyWith(color: c.emerald),
                        ),
                        const SizedBox(height: Space.xxs),
                        Semantics(header: true, child: Text(titles[step], style: context.text.headlineSmall)),
                      ],
                    ),
                    const SizedBox(height: Space.lg),
                    KeyedSubtree(
                      key: anchor(targets.wizardContent),
                      child: switch (step) {
                        0 => PurposeStep(editId: editId),
                        1 => TypeStep(editId: editId),
                        2 => LocationStep(editId: editId),
                        3 => DetailsStep(editId: editId),
                        4 => PriceStep(editId: editId),
                        5 => AmenitiesStep(editId: editId),
                        6 => DescriptionStep(editId: editId),
                        7 => MediaStep(editId: editId),
                        _ => PreviewStep(editId: editId),
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Every step, the review included, keeps Back in the same place.
            _StepBar(
              nextKey: targets.wizardNext,
              onBack: step == 0 || s.saving ? null : back,
              onNext: last
                  ? null
                  : () {
                      final problem = stepProblem(context, ref, editId, step);
                      if (problem != null) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(problem)));
                        unawaited(HapticFeedback.heavyImpact());
                        return;
                      }
                      FocusScope.of(context).unfocus();
                      ctrl.goTo(step + 1);
                    },
            ),
          ],
        ),
      ),
    );
    return s.editing ? screen : _ListingTour(child: screen);
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.onBack, required this.onNext, this.nextKey});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final Key? nextKey;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: Layout.inset(context, top: Space.sm, bottom: Space.sm),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (onBack != null) OutlinedButton(onPressed: onBack, child: Text(l.actionBack)),
            const Spacer(),
            if (onNext != null) FilledButton(key: nextKey, onPressed: onNext, child: Text(l.actionNext)),
          ],
        ),
      ),
    );
  }
}

/// Runs the listing tour once, the first time someone starts a listing (or
/// when it is asked for from Profile).
class _ListingTour extends ConsumerStatefulWidget {
  const _ListingTour({required this.child});
  final Widget child;

  @override
  ConsumerState<_ListingTour> createState() => _ListingTourState();
}

class _ListingTourState extends ConsumerState<_ListingTour> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        maybeRunTour(
          context,
          ref,
          TourId.listing,
          visible: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
