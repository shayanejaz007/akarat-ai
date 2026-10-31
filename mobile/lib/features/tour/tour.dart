import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/coach_marks.dart';
import '../../shared/services/supabase_providers.dart';
import 'tour_store.dart';

/// The guided tours. The main one welcomes a new account after sign-up (and
/// a first-time guest); the others explain their screen the first time it
/// is reached. All can be replayed from Profile → Guides.
enum TourId {
  /// Finding, saving and listing: Home's search, Buy/Rent, city, the tabs.
  explore,

  /// Reading and filtering the Explore map.
  map,

  /// How the listing form works.
  listing,

  /// A listing: its photos, saving it, contacting the owner.
  property,
}

/// The controls the tours point at. One instance per app, so each key is
/// attached to exactly one widget.
class TourTargets {
  final homeSearch = GlobalKey(debugLabel: 'tour.homeSearch');
  final homeDeal = GlobalKey(debugLabel: 'tour.homeDeal');
  final homeCity = GlobalKey(debugLabel: 'tour.homeCity');
  final navExplore = GlobalKey(debugLabel: 'tour.navExplore');
  final navAi = GlobalKey(debugLabel: 'tour.navAi');
  final navSaved = GlobalKey(debugLabel: 'tour.navSaved');
  final navProfile = GlobalKey(debugLabel: 'tour.navProfile');

  /// The tab bar's keys in the shell's order (NavTab); Home and Daily have
  /// none. The shell and the tests take the list from here so they cannot
  /// drift apart when a tab is added.
  List<Key?> get navTabs => [null, navExplore, null, navAi, navSaved, navProfile];

  final mapDeal = GlobalKey(debugLabel: 'tour.mapDeal');
  final mapLegend = GlobalKey(debugLabel: 'tour.mapLegend');
  final mapFilters = GlobalKey(debugLabel: 'tour.mapFilters');
  final mapToggle = GlobalKey(debugLabel: 'tour.mapToggle');
  final mapLayer = GlobalKey(debugLabel: 'tour.mapLayer');

  final wizardProgress = GlobalKey(debugLabel: 'tour.wizardProgress');
  final wizardContent = GlobalKey(debugLabel: 'tour.wizardContent');
  final wizardNext = GlobalKey(debugLabel: 'tour.wizardNext');
  final wizardClose = GlobalKey(debugLabel: 'tour.wizardClose');

  final propertyPhotos = GlobalKey(debugLabel: 'tour.propertyPhotos');
  final propertySave = GlobalKey(debugLabel: 'tour.propertySave');
  final propertyContact = GlobalKey(debugLabel: 'tour.propertyContact');
}

final tourTargetsProvider = Provider<TourTargets>((ref) => TourTargets());

/// A tour asked for from Profile, waiting for its screen to come up.
final pendingTourProvider = NotifierProvider<PendingTour, TourId?>(PendingTour.new);

class PendingTour extends Notifier<TourId?> {
  @override
  TourId? build() => null;

  void request(TourId id) {
    // Through null, so asking twice for the same tour still notifies.
    state = null;
    state = id;
  }

  void clear() => state = null;
}

/// The steps of [id]. Text is looked up as each card is drawn, so it
/// follows the current language.
List<CoachStep> _steps(
  TourId id,
  TourTargets t, {
  required bool signedIn,
  required bool welcome,
  required bool brief,
  required String firstName,
}) => switch (id) {
  TourId.explore => [
    // A new account is greeted before the tour proper.
    if (welcome)
      CoachStep(
        title: (l) => firstName.isEmpty ? l.tourWelcomeTitle : l.tourWelcomeTitleName(firstName),
        body: (l) => brief ? l.tourWelcomeAccountBody : l.tourWelcomeBody,
      ),
    // Shown round once already, as a guest: only what the account adds.
    if (!brief) ...[
      CoachStep(target: t.homeSearch, title: (l) => l.tourSearchTitle, body: (l) => l.tourSearchBody),
      CoachStep(target: t.homeDeal, title: (l) => l.tourDealTitle, body: (l) => l.tourDealBody),
      CoachStep(target: t.homeCity, title: (l) => l.tourCityTitle, body: (l) => l.tourCityBody),
      CoachStep(target: t.navExplore, title: (l) => l.tourExploreTitle, body: (l) => l.tourExploreBody),
      CoachStep(target: t.navAi, title: (l) => l.tourAiTitle, body: (l) => l.tourAiBody),
    ],
    CoachStep(target: t.navSaved, title: (l) => l.tourSavedTitle, body: (l) => l.tourSavedBody),
    // Signed out, that tab is the Log in button.
    CoachStep(
      target: t.navProfile,
      title: (l) => l.tourProfileTitle,
      body: (l) => signedIn ? l.tourProfileBody : l.tourProfileGuestBody,
    ),
  ],
  TourId.map => [
    CoachStep(target: t.mapDeal, title: (l) => l.tourMapDealTitle, body: (l) => l.tourMapDealBody),
    CoachStep(target: t.mapLegend, title: (l) => l.tourMapPinsTitle, body: (l) => l.tourMapPinsBody),
    CoachStep(target: t.mapFilters, title: (l) => l.tourMapFiltersTitle, body: (l) => l.tourMapFiltersBody),
    // Only on Google's maps; the tour skips it where there is no satellite view.
    CoachStep(target: t.mapLayer, title: (l) => l.tourMapLayerTitle, body: (l) => l.tourMapLayerBody),
    CoachStep(target: t.mapToggle, title: (l) => l.tourMapToggleTitle, body: (l) => l.tourMapToggleBody),
  ],
  TourId.listing => [
    CoachStep(target: t.wizardProgress, title: (l) => l.tourStepsTitle, body: (l) => l.tourStepsBody),
    CoachStep(target: t.wizardContent, title: (l) => l.tourOneThingTitle, body: (l) => l.tourOneThingBody),
    CoachStep(target: t.wizardNext, title: (l) => l.tourNextTitle, body: (l) => l.tourNextBody),
    CoachStep(target: t.wizardClose, title: (l) => l.tourCloseTitle, body: (l) => l.tourCloseBody, circle: true),
  ],
  TourId.property => [
    CoachStep(target: t.propertyPhotos, title: (l) => l.tourPhotosTitle, body: (l) => l.tourPhotosBody),
    CoachStep(target: t.propertySave, title: (l) => l.tourSaveTitle, body: (l) => l.tourSaveBody),
    CoachStep(target: t.propertyContact, title: (l) => l.tourContactTitle, body: (l) => l.tourContactBody),
  ],
};

/// Whether a tour is on screen, so two never stack. One per app.
final _tourShowingProvider = Provider<_Flag>((ref) => _Flag());

class _Flag {
  bool value = false;
}

/// Shows [id] now if it is due (see [TourStore.shouldStart]) or was asked
/// for from Profile. [visible] says whether the calling screen is the one on
/// show; a screen in a background tab never starts a tour. Checked again
/// after a short settle, in case the reader moved on.
Future<void> maybeRunTour(BuildContext context, WidgetRef ref, TourId id, {required bool Function() visible}) async {
  final store = ref.read(tourStoreProvider);
  final showing = ref.read(_tourShowingProvider);
  bool wanted() => ref.read(pendingTourProvider) == id || store.shouldStart(id);
  if (showing.value || !visible() || !wanted()) return;
  showing.value = true;
  try {
    // Let the screen settle (route transition, first data) before measuring.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!context.mounted || !visible() || !wanted()) return;
    final replay = ref.read(pendingTourProvider) == id;
    if (replay) ref.read(pendingTourProvider.notifier).clear();
    final user = ref.read(currentUserProvider);
    final name = ((user?.userMetadata?['full_name'] as String?) ?? '').trim();
    final welcome = id == TourId.explore && store.welcomeOwed && !replay;
    final steps = _steps(
      id,
      ref.read(tourTargetsProvider),
      signedIn: user != null,
      welcome: welcome,
      brief: welcome && store.done(TourId.explore),
      firstName: name.split(RegExp(r'\s+')).first,
    );
    final outcome = await showCoachMarks(
      context,
      steps,
      // A tour cut short (the app closed, a link opened) picks up where it was.
      start: replay ? 0 : store.step(id, welcome: welcome),
      onStep: (i) => unawaited(store.setStep(id, i, welcome: welcome)),
    );
    // Finished or skipped: not offered again, here or on the account.
    if (outcome != CoachOutcome.interrupted) await store.markDone(id);
  } finally {
    showing.value = false;
  }
}
