import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/geo.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/maps.dart';
import '../../core/widgets/place_picker.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/daily_models.dart' show isoDay;
import '../../shared/reference/places.dart';
import '../../shared/reference/places_provider.dart';
import '../../shared/services/supabase_providers.dart';
import 'services_models.dart';
import 'services_repository.dart';
import 'services_ui.dart';

/// Asking for a service: what, where, when, how urgent, photos and how to
/// reach the person. Checked here with the same rules the database applies
/// (create_service_request(), 0024_services.sql), which checks them all
/// again. One token per submission: pressing Send again after a dropped
/// connection returns the first request instead of making a second.
class ServiceRequestScreen extends ConsumerStatefulWidget {
  const ServiceRequestScreen({super.key, this.categoryId});
  final String? categoryId;

  @override
  ConsumerState<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends ConsumerState<ServiceRequestScreen> {
  final _picker = ImagePicker();
  final _custom = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  String _token = ServicesRepository.newToken();
  String? _category;
  PlaceSel? _place;
  LatLngPoint? _pin;
  DateTime _date = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
  String _window = 'any';
  String _urgency = 'normal';
  final _photos = <File>[];
  Map<String, String> _errors = {};
  String? _alert;
  bool _busy = false;
  String? _progress;
  ServiceCreated? _done;

  @override
  void initState() {
    super.initState();
    _category = widget.categoryId;
    final user = ref.read(currentUserProvider);
    if (user != null) {
      _name.text = '${user.userMetadata?['full_name'] ?? ''}'.trim();
      _phone.text = (user.phone ?? '').isEmpty ? '' : '+${user.phone!.replaceFirst('+', '')}';
      _email.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_custom, _desc, _address, _name, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear(String key) {
    if (_errors.containsKey(key)) setState(() => _errors = {..._errors}..remove(key));
  }

  /// The same rules as create_service_request(); the database checks again.
  Map<String, String> _validate(List<ServiceCategory> cats) {
    final e = <String, String>{};
    final cat = cats.where((c) => c.id == _category).firstOrNull;
    if (cat == null) e['category_id'] = 'category_id';
    final custom = _custom.text.trim();
    if (cat != null && cat.custom && (custom.length < 2 || custom.length > 80)) e['custom_service'] = 'custom_service';
    if (_desc.text.trim().length < 10) e['description'] = 'description';
    if (_place?.city == null) e['city_id'] = 'city_id';
    if (_address.text.trim().length < 3) e['address'] = 'address';
    final today = DateUtils.dateOnly(DateTime.now());
    if (_date.isBefore(today) || _date.isAfter(today.add(const Duration(days: 180)))) {
      e['preferred_date'] = 'preferred_date';
    }
    if (_name.text.trim().length < 2) e['contact_name'] = 'contact_name';
    final phone = _phone.text.trim();
    final digits = phone.replaceAll(RegExp('[^0-9]'), '');
    if (!RegExp(r'^\+?[0-9][0-9 ()-]{5,22}$').hasMatch(phone) || digits.length < 7 || digits.length > 15) {
      e['contact_phone'] = 'contact_phone';
    }
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      e['contact_email'] = 'contact_email';
    }
    final pin = _pin;
    if (pin != null && !(pin.lat >= 29 && pin.lat <= 33.5 && pin.lng >= 34.8 && pin.lng <= 39.5)) e['lat'] = 'lat';
    return e;
  }

  static String _text(AppLocalizations l, String code) => switch (code) {
    'category_id' => l.svErrCategory,
    'custom_service' => l.svErrCustom,
    'description' => l.svErrDesc,
    'governorate_id' || 'city_id' => l.svErrPlace,
    'neighborhood_id' => l.svErrHood,
    'address' => l.svErrAddress,
    'lat' => l.svErrPin,
    'preferred_date' => l.svErrDate,
    'photos' => l.svErrPhotos,
    'contact_name' => l.svErrName,
    'contact_phone' => l.svErrPhone,
    'contact_email' => l.svErrEmail,
    'too_many' => l.svErrTooMany,
    'sign_in' => l.svErrSignIn,
    'photo_type' => l.svErrPhotoType,
    'photo_size' => l.svErrPhotoSize,
    'photo_count' => l.svErrPhotoCount,
    'not_set_up' => l.servicesNotReady,
    'network' => l.svErrNetwork,
    'fix' => l.svFixBelow,
    _ => l.svErrOther,
  };

  String? _err(AppLocalizations l, String key) => _errors[key] == null ? null : _text(l, _errors[key]!);

  Future<void> _addPhotos() async {
    final room = ServicesRepository.maxPhotos - _photos.length;
    if (room <= 0) return;
    final picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 85, limit: room);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _photos.addAll(picked.take(room).map((x) => File(x.path)));
      // Other photos are another submission: a retry must not find the old files.
      _token = ServicesRepository.newToken();
      _errors = {..._errors}..remove('photos');
    });
  }

  void _setPlace(PlaceSel? sel) {
    setState(() {
      _place = sel;
      _errors = {..._errors}
        ..remove('city_id')
        ..remove('neighborhood_id');
    });
  }

  void _setPin(LatLngPoint p) {
    setState(() {
      _pin = p;
      _errors = {..._errors}..remove('lat');
      // A pin names the area when none is chosen yet.
      if (_place?.city == null) {
        final near = ref.read(placesNowProvider).places.nearest(p.lat, p.lng);
        if (near.city != null) _place = near;
      }
    });
  }

  Future<void> _submit(List<ServiceCategory> cats) async {
    final l = context.l10n;
    final lang = context.lang;
    final errors = _validate(cats);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _alert = 'fix';
      });
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
      _alert = null;
    });
    final repo = ref.read(servicesRepositoryProvider);
    try {
      final paths = _photos.isEmpty
          ? const <String>[]
          : await repo.uploadPhotos(
              _photos,
              _token,
              onProgress: (i, n) {
                if (mounted) setState(() => _progress = l.svUploading('$i', '$n'));
              },
            );
      if (mounted) setState(() => _progress = l.svSending);
      final out = await repo.create({
        'client_token': _token,
        'category_id': _category,
        'custom_service': _custom.text.trim().isEmpty ? null : _custom.text.trim(),
        'description': _desc.text.trim(),
        'governorate_id': _place?.gov,
        'city_id': _place?.city,
        'neighborhood_id': _place?.hood,
        'address': _address.text.trim(),
        'lat': _pin?.lat,
        'lng': _pin?.lng,
        'preferred_date': isoDay(_date),
        'preferred_window': _window,
        'urgency': _urgency,
        'photos': paths,
        'contact_name': _name.text.trim(),
        'contact_phone': _phone.text.trim(),
        'contact_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'lang': lang,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      ref.invalidate(myServiceRequestsProvider);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _done = out;
        });
      }
    } on ServiceRefusal catch (e) {
      final field = e.field ?? (e.code.startsWith('photo_') ? 'photos' : null);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _errors = field == null ? {} : {field: e.code.startsWith('photo_') ? e.code : field};
          _alert = field == null ? e.code : 'fix';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _alert = e is AppFailure && e.isOffline ? 'network' : 'other';
        });
      }
    }
  }

  void _again() => setState(() {
    _done = null;
    _token = ServicesRepository.newToken();
    for (final c in [_custom, _desc, _address]) {
      c.clear();
    }
    _photos.clear();
    _pin = null;
    _urgency = 'normal';
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cats = ref.watch(serviceCategoriesProvider);
    final done = _done;
    return Scaffold(
      appBar: AppBar(title: Text(done == null ? l.servicesRequest : l.servicesTitle)),
      body: done != null
          ? _Done(created: done, onAgain: _again)
          : cats.when(
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) => e is ServiceRefusal && e.code == 'not_set_up'
                  ? EmptyState(icon: Icons.handyman_outlined, title: l.servicesNotReady)
                  : ErrorState(error: e, onRetry: () => ref.invalidate(serviceCategoriesProvider)),
              data: (list) => _form(context, list),
            ),
    );
  }

  Widget _section(BuildContext context, int n, String title, List<Widget> children) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.card,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: c.ink,
                child: Text('$n', style: context.text.labelSmall?.copyWith(color: c.surface)),
              ),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(title, style: context.text.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.md),
          ...children,
        ],
      ),
    );
  }

  Widget _form(BuildContext context, List<ServiceCategory> cats) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final places = ref.watch(placesNowProvider).places;
    final cat = cats.where((x) => x.id == _category).firstOrNull;
    final centre = places.centre(_place);
    final pin = _pin;
    final near = pin == null ? '' : nearPlaceLabel(places, pin.lat, pin.lng, lang, l.placeNear);
    const gap = SizedBox(height: Space.sm);

    return ListView(
      padding: Layout.inset(context).copyWith(top: Space.md, bottom: Space.xxl),
      children: [
        Text(l.svFormBody, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
        const SizedBox(height: Space.md),

        _section(context, 1, l.svService, [
          DropdownButtonFormField<String>(
            initialValue: cat?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l.svChooseService,
              errorText: _err(l, 'category_id'),
              errorMaxLines: 3,
              counterText: '',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(Space.xs),
                child: Icon(serviceIcon(cat?.icon ?? 'maintenance'), color: c.emerald),
              ),
            ),
            items: [
              for (final x in cats)
                DropdownMenuItem(
                  value: x.id,
                  child: Text(x.name(lang), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _category = v;
              _errors = {..._errors}..remove('category_id');
            }),
          ),
          if (cat != null && cat.examples(lang).isNotEmpty) ...[
            const SizedBox(height: Space.xxs),
            Text(cat.examples(lang), style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
          ],
          if (cat?.custom ?? false) ...[
            gap,
            TextField(
              controller: _custom,
              maxLength: 80,
              onChanged: (_) => _clear('custom_service'),
              decoration: InputDecoration(
                labelText: l.svCustom,
                hintText: l.svCustomHint,
                errorText: _err(l, 'custom_service'),
                errorMaxLines: 3,
                counterText: '',
              ),
            ),
          ],
          gap,
          TextField(
            controller: _desc,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _clear('description'),
            decoration: InputDecoration(
              labelText: l.svDesc,
              hintText: l.svDescHint,
              alignLabelWithHint: true,
              errorText: _err(l, 'description'),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
        ]),

        _section(context, 2, l.svWhere, [
          PlaceField(
            label: l.svPlace,
            value: _place,
            onChanged: _setPlace,
            requireCity: true,
            errorText: _err(l, 'city_id') ?? _err(l, 'neighborhood_id'),
          ),
          gap,
          TextField(
            controller: _address,
            maxLength: 300,
            onChanged: (_) => _clear('address'),
            decoration: InputDecoration(
              labelText: l.svAddress,
              hintText: l.svAddressHint,
              errorText: _err(l, 'address'),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
          const SizedBox(height: Space.md),
          Text(l.svPin, style: context.text.titleSmall),
          const SizedBox(height: Space.xxs),
          Text(l.svPinHint, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
          gap,
          ClipRRect(
            borderRadius: Radii.card,
            child: SizedBox(
              height: 240,
              child: PinPicker(
                initial: pin,
                center: centre == null ? Geo.jordanCenter : LatLngPoint(centre.lat, centre.lng),
                centerZoom: centre?.zoom ?? 8,
                onChanged: _setPin,
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Icon(
                pin == null ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                size: 18,
                color: pin == null ? c.inkFaint : c.emerald,
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (near.isNotEmpty) Text(near, style: context.text.bodyMedium),
                    Text(
                      pin == null ? l.svPinNone : '${pin.lat.toStringAsFixed(5)}, ${pin.lng.toStringAsFixed(5)}',
                      textDirection: TextDirection.ltr,
                      style: context.text.bodySmall?.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
              ),
              if (pin != null) TextButton(onPressed: () => setState(() => _pin = null), child: Text(l.svPinRemove)),
            ],
          ),
          if (_err(l, 'lat') case final e?) Text(e, style: context.text.bodySmall?.copyWith(color: c.danger)),
        ]),

        _section(context, 3, l.svWhen, [
          InkWell(
            borderRadius: Radii.field,
            onTap: () async {
              final today = DateUtils.dateOnly(DateTime.now());
              final d = await showDatePicker(
                context: context,
                initialDate: _date.isBefore(today) ? today : _date,
                firstDate: today,
                lastDate: today.add(const Duration(days: 180)),
              );
              if (d != null) {
                setState(() {
                  _date = d;
                  _errors = {..._errors}..remove('preferred_date');
                });
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l.svDate,
                errorText: _err(l, 'preferred_date'),
                errorMaxLines: 3,
                counterText: '',
                prefixIcon: const Icon(Icons.event_outlined),
              ),
              child: Text(Fmt.night(_date, lang: lang), style: context.text.bodyLarge),
            ),
          ),
          gap,
          DropdownButtonFormField<String>(
            initialValue: _window,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.svWindow, prefixIcon: const Icon(Icons.schedule_rounded)),
            items: [
              for (final w in const ['any', 'morning', 'afternoon', 'evening'])
                DropdownMenuItem(value: w, child: Text(serviceWindowLabel(l, w))),
            ],
            onChanged: (v) => setState(() => _window = v ?? 'any'),
          ),
          const SizedBox(height: Space.md),
          Text(l.svUrgency, style: context.text.titleSmall),
          const SizedBox(height: Space.xs),
          for (final (key, title, note, tone) in [
            ('normal', l.svUrgNormal, l.svUrgNormalNote, c.emerald),
            ('urgent', l.svUrgUrgent, l.svUrgUrgentNote, c.warning),
            ('emergency', l.svUrgEmergency, l.svUrgEmergencyNote, c.danger),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: _UrgencyTile(
                title: title,
                note: note,
                tone: tone,
                selected: _urgency == key,
                onTap: () => setState(() => _urgency = key),
              ),
            ),
          if (_urgency == 'emergency')
            NoticeLine(icon: Icons.warning_amber_rounded, text: l.svEmergencyWarning, tone: c.danger),
        ]),

        _section(context, 4, l.svPhotos, [
          Text(l.svPhotosHint, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
          gap,
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final (i, f) in _photos.indexed)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: Image.file(f, width: 92, height: 92, fit: BoxFit.cover),
                    ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        tooltip: l.svRemovePhoto,
                        onPressed: () => setState(() {
                          _photos.removeAt(i);
                          _token = ServicesRepository.newToken();
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              if (_photos.length < ServicesRepository.maxPhotos)
                InkWell(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  onTap: () => unawaited(_addPhotos()),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: c.border),
                      color: c.surfaceMuted,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: c.inkMuted),
                        const SizedBox(height: Space.xxs),
                        Text(l.svAddPhotos, style: context.text.labelSmall, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_err(l, 'photos') case final e?) ...[
            gap,
            Text(e, style: context.text.bodySmall?.copyWith(color: c.danger)),
          ],
        ]),

        _section(context, 5, l.svContact, [
          TextField(
            controller: _name,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            onChanged: (_) => _clear('contact_name'),
            decoration: InputDecoration(
              labelText: l.svName,
              errorText: _err(l, 'contact_name'),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
          TextField(
            controller: _phone,
            maxLength: 24,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textDirection: TextDirection.ltr,
            onChanged: (_) => _clear('contact_phone'),
            decoration: InputDecoration(
              labelText: l.svPhone,
              hintText: '07 9123 4567',
              errorText: _err(l, 'contact_phone'),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
          TextField(
            controller: _email,
            maxLength: 200,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textDirection: TextDirection.ltr,
            onChanged: (_) => _clear('contact_email'),
            decoration: InputDecoration(
              labelText: l.svEmail,
              errorText: _err(l, 'contact_email'),
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
        ]),

        if (_alert case final a?) ...[
          NoticeLine(icon: Icons.error_outline_rounded, text: _text(l, a), tone: c.danger),
          gap,
        ],
        BusyButton(
          label: _busy ? (_progress ?? l.svSending) : l.svSend,
          icon: Icons.send_rounded,
          onPressed: _busy ? null : () => _submit(cats),
        ),
        gap,
        NoticeLine(icon: Icons.verified_user_outlined, text: l.svPrivacy),
      ],
    );
  }
}

class _UrgencyTile extends StatelessWidget {
  const _UrgencyTile({
    required this.title,
    required this.note,
    required this.tone,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String note;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? tone.withValues(alpha: 0.08) : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.field,
          side: BorderSide(color: selected ? tone : c.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: Radii.field,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? tone : c.inkFaint,
                  size: 20,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall?.copyWith(color: selected ? tone : null)),
                      Text(note, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
                    ],
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

/// Sent: the reference from the database, and what happens next.
class _Done extends StatelessWidget {
  const _Done({required this.created, required this.onAgain});
  final ServiceCreated created;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return ListView(
      padding: Layout.inset(context).copyWith(top: Space.xxl, bottom: Space.xxl),
      children: [
        Center(
          child: CircleAvatar(
            radius: 34,
            backgroundColor: c.emerald,
            child: Icon(Icons.check_rounded, color: c.onForest, size: 36),
          ),
        ),
        const SizedBox(height: Space.md),
        Text(l.svDoneTitle, textAlign: TextAlign.center, style: context.text.headlineSmall),
        const SizedBox(height: Space.xs),
        Text(
          l.svDoneBody,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: c.inkMuted, height: 1.5),
        ),
        const SizedBox(height: Space.lg),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.sm),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: Radii.card,
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                Text(l.svDoneRef, style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
                SelectableText(
                  created.ref,
                  textDirection: TextDirection.ltr,
                  style: context.text.headlineSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (created.duplicate) ...[
          const SizedBox(height: Space.sm),
          Text(l.svDoneDup, textAlign: TextAlign.center, style: context.text.bodySmall),
        ],
        const SizedBox(height: Space.xl),
        FilledButton(onPressed: () => context.pushReplacement(Routes.myServiceRequests), child: Text(l.svSeeMine)),
        const SizedBox(height: Space.xs),
        OutlinedButton(onPressed: onAgain, child: Text(l.svAnother)),
      ],
    );
  }
}
