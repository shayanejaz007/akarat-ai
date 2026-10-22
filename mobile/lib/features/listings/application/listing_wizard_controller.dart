import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/utils/geo.dart';
import '../../../shared/models/listing.dart';
import '../../../shared/repositories/listings_repository.dart';
import '../../../shared/repositories/media_repository.dart';
import '../../../shared/services/preferences.dart';
import '../../../shared/services/refresh.dart';
import '../../dashboard/dashboard_providers.dart';
import '../domain/listing_draft.dart';

/// Why a save could not start. Shown inline on the step that needs fixing.
enum DraftProblem { title, price, city }

class WizardState {
  const WizardState({
    required this.draft,
    this.step = 0,
    this.loading = false,
    this.original,
    this.saving = false,
    this.uploadDone = 0,
    this.uploadTotal = 0,
    this.error,
    this.restored = false,
    this.removedPaths = const [],
  });

  final ListingDraft draft;
  final int step;

  /// Editing: the stored listing is being fetched.
  final bool loading;

  /// Editing: the listing as stored. Null for a new listing.
  final Listing? original;
  final bool saving;
  final int uploadDone;
  final int uploadTotal;
  final Object? error;

  /// A new listing picked up from a draft saved on this device.
  final bool restored;

  /// Storage paths of files removed during this edit. Deleted from Storage
  /// only after the row no longer references them.
  final List<String> removedPaths;

  bool get editing => original != null;

  WizardState copyWith({
    ListingDraft? draft,
    int? step,
    bool? loading,
    Listing? original,
    bool? saving,
    int? uploadDone,
    int? uploadTotal,
    Object? error,
    bool clearError = false,
    bool? restored,
    List<String>? removedPaths,
  }) => WizardState(
    draft: draft ?? this.draft,
    step: step ?? this.step,
    loading: loading ?? this.loading,
    original: original ?? this.original,
    saving: saving ?? this.saving,
    uploadDone: uploadDone ?? this.uploadDone,
    uploadTotal: uploadTotal ?? this.uploadTotal,
    error: clearError ? null : (error ?? this.error),
    restored: restored ?? this.restored,
    removedPaths: removedPaths ?? this.removedPaths,
  );
}

final listingWizardProvider = NotifierProvider.autoDispose.family<ListingWizardController, WizardState, String?>(
  ListingWizardController.new,
);

class ListingWizardController extends Notifier<WizardState> {
  ListingWizardController(this.editId);

  /// The listing being edited, or null for a new one.
  final String? editId;
  Timer? _persist;

  static const stepCount = 9;

  @override
  WizardState build() {
    ref.onDispose(() => _persist?.cancel());
    if (editId != null) {
      scheduleMicrotask(_loadForEdit);
      return const WizardState(draft: ListingDraft(), loading: true);
    }
    final saved = ListingDraft.fromJson(ref.read(preferencesProvider).listingDraft);
    return WizardState(draft: saved ?? const ListingDraft(), restored: saved != null && saved.isDirty);
  }

  Future<void> _loadForEdit() async {
    final repo = ref.read(listingsRepositoryProvider);
    try {
      final row = await repo.byId(editId!);
      if (row == null) throw const AppFailure(FailureKind.notFound);
      var draft = ListingDraft.fromListing(row);
      // Reopen on the real point, not the blurred one: editing a blurred pin
      // would walk the published point further away on every save.
      final exact = await repo.exactLocation(row.id);
      if (exact != null) {
        draft = draft.copyWith(lat: exact.lat, lng: exact.lng, address: exact.address ?? draft.address);
      }
      state = WizardState(draft: draft, original: row);
    } on Object catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  void update(ListingDraft Function(ListingDraft) change) {
    state = state.copyWith(draft: change(state.draft), clearError: true);
    _schedulePersist();
  }

  /// New listings are kept on the device as they are typed, so leaving the
  /// form — or the app being killed — never loses them. Edits are not: the
  /// stored listing is already the saved copy.
  void _schedulePersist() {
    if (state.editing) return;
    _persist?.cancel();
    _persist = Timer(const Duration(milliseconds: 500), () {
      unawaited(ref.read(preferencesProvider).setListingDraft(state.draft.toJson()));
    });
  }

  Future<void> discardDraft() async {
    _persist?.cancel();
    await ref.read(preferencesProvider).setListingDraft(null);
    state = const WizardState(draft: ListingDraft());
  }

  void goTo(int step) => state = state.copyWith(step: step.clamp(0, stepCount - 1), clearError: true);

  /// Drops a file. One already in Storage is remembered for deletion after
  /// the save; one only picked locally is just forgotten.
  void removeMedia(int index) {
    final media = [...state.draft.media];
    final removed = media.removeAt(index);
    final path = removed.stored?.path;
    state = state.copyWith(
      draft: state.draft.copyWith(media: media),
      removedPaths: removed.existing != null && path != null ? [...state.removedPaths, path] : state.removedPaths,
    );
    _schedulePersist();
  }

  /// Snaps a dropped pin onto the city/area taxonomy. The dropdowns remain
  /// the source of truth for city_id and neighborhood_id.
  void setPin(LatLngPoint p) {
    final area = Geo.nearestArea(p);
    update(
      (d) => d.copyWith(
        lat: p.lat,
        lng: p.lng,
        cityId: area.cityId ?? d.cityId,
        neighborhoodId: area.neighborhoodId,
        clearNeighborhood: area.neighborhoodId == null,
      ),
    );
  }

  List<DraftProblem> problems() {
    final d = state.draft;
    return [
      if (d.titleEn.trim().isEmpty && d.titleAr.trim().isEmpty) DraftProblem.title,
      if ((ListingDraft.number(d.price) ?? 0) <= 0) DraftProblem.price,
      if (d.cityId == null || d.cityId!.isEmpty) DraftProblem.city,
    ];
  }

  /// Saves the listing. Mirrors the website's submitListing step for step:
  ///
  /// 1. upload new files first, so a storage failure never leaves a row
  ///    pointing at files that are not there;
  /// 2. publish the exact pin only if the owner chose exact, otherwise the
  ///    deterministic blurred point;
  /// 3. write the row (status active, or draft when asked);
  /// 4. write the exact pin to the owner-only table, best effort;
  /// 5. delete files removed during an edit, now nothing references them.
  ///
  /// Returns the saved listing, or null when it failed (see [WizardState.error]).
  Future<Listing?> save({required bool publish}) async {
    if (state.saving) return null;
    if (problems().isNotEmpty) return null;
    state = state.copyWith(saving: true, clearError: true);
    final media = ref.read(mediaRepositoryProvider);
    final repo = ref.read(listingsRepositoryProvider);

    try {
      // 1. Uploads, in the order the owner arranged them (the first is the cover).
      final pending = state.draft.media.where((m) => m.stored == null).length;
      state = state.copyWith(uploadDone: 0, uploadTotal: pending);
      final arranged = <DraftMedia>[];
      for (final m in state.draft.media) {
        if (m.stored != null) {
          arranged.add(m);
          continue;
        }
        final uploaded = await media.upload(File(m.localPath!), video: m.isVideo);
        arranged.add(m.withUploaded(uploaded));
        // Keep progress in the draft itself, so a later failure and retry
        // does not upload this file a second time.
        state = state.copyWith(
          draft: state.draft.copyWith(media: [...arranged, ...state.draft.media.skip(arranged.length)]),
          uploadDone: state.uploadDone + 1,
        );
      }

      final d = state.draft;
      // 2. The publishable point.
      final exact = d.precision == LocationPrecision.exact;
      final pub = !d.hasPin ? null : (exact ? LatLngPoint(d.lat!, d.lng!) : Geo.blur(d.lat!, d.lng!));
      final geoSchema = state.original?.locationPrecision != null || state.original == null;

      final title = (en: d.titleEn.trim(), ar: d.titleAr.trim());
      final columns = <String, Object?>{
        'deal': d.deal.name,
        'property_type': d.propertyType,
        'city_id': d.cityId,
        'neighborhood_id': d.neighborhoodId,
        'price_jod': ListingDraft.number(d.price),
        'bedrooms': ListingDraft.number(d.bedrooms),
        'bathrooms': ListingDraft.number(d.bathrooms),
        'area_sqm': ListingDraft.number(d.areaSqm),
        'land_sqm': ListingDraft.number(d.landSqm),
        'year_built': ListingDraft.number(d.yearBuilt),
        // One title is required; the other falls back to it rather than null.
        'title_en': title.en.isNotEmpty ? title.en : title.ar,
        'title_ar': title.ar.isNotEmpty ? title.ar : title.en,
        'lat': pub?.lat,
        'lng': pub?.lng,
        if (d.hasPin || geoSchema) ...{
          'location_precision': d.precision.name,
          // An address is published only with the exact pin; next to a
          // blurred point it would give the blur away.
          'address': d.hasPin && exact && d.address.trim().isNotEmpty ? d.address.trim() : null,
        },
      };
      final payload = ListingPayload(
        amenities: d.amenities,
        descriptionEn: d.descriptionEn,
        descriptionAr: d.descriptionAr,
        media: [for (final m in d.media) m.stored!],
        contact: ListingContact(phone: d.contactPhone.trim(), whatsapp: true, messaging: true),
      );

      // 3. The row. Editing never touches status: a hidden listing stays
      // hidden after a correction.
      final saved = state.original != null
          ? await repo.update(state.original!.id, columns, payload)
          : await repo.create({...columns, 'status': publish ? 'active' : 'draft'}, payload);

      // 4. The exact pin, owner-only. Not fatal: the listing is saved.
      if (d.hasPin) {
        try {
          await repo.saveExactLocation(
            saved.id,
            lat: d.lat!,
            lng: d.lng!,
            address: d.address.trim().isEmpty ? null : d.address.trim(),
          );
        } on Object {
          // property_locations unavailable; the public point is already set.
        }
      }

      // 5. Files dropped during the edit.
      await media.remove(state.removedPaths);

      if (state.original == null) await ref.read(preferencesProvider).setListingDraft(null);
      ref.read(refreshTickProvider.notifier).bump();
      ref.invalidate(myListingsProvider);
      state = state.copyWith(saving: false, removedPaths: const []);
      return saved;
    } on Object catch (e) {
      state = state.copyWith(saving: false, error: AppFailure.from(e));
      _schedulePersist();
      return null;
    }
  }
}
