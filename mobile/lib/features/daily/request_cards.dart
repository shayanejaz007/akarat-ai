import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/listing_image.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/models/daily_models.dart';
import '../../shared/repositories/daily_repository.dart';
import '../../shared/services/supabase_providers.dart';
import 'daily_providers.dart';

/// The pill for a request's state, in the same four tones everywhere.
({String label, Color color}) bookingTone(BuildContext context, BookingRequest r) {
  final t = context.l10n;
  final c = context.colors;
  if (r.expiredOn(DateTime.now())) return (label: t.bookingStatusExpired, color: c.inkMuted);
  return switch (r.status) {
    BookingStatus.pending => (label: t.bookingStatusPending, color: c.warning),
    BookingStatus.approved => (label: t.bookingStatusApproved, color: c.emerald),
    BookingStatus.confirmed => (label: t.bookingStatusConfirmed, color: c.emerald),
    BookingStatus.rejected => (label: t.bookingStatusRejected, color: c.danger),
    BookingStatus.cancelled => (label: t.bookingStatusCancelled, color: c.inkMuted),
  };
}

String _dates(BookingRequest r, String lang) => Fmt.stay(r.checkIn, r.checkOut, lang: lang);

String _facts(BuildContext context, BookingRequest r) {
  final t = context.l10n;
  return '${t.dailyNights(r.nights)} · ${t.dailyGuests(r.guests)} · ${Fmt.price(r.totalPrice, lang: context.lang)}';
}

/// Runs a request action, then refreshes every list that shows requests.
Future<bool> _act(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = context.failureMessage;
  final done = context.l10n.bookingUpdated;
  try {
    await action();
    ref
      ..invalidate(myBookingsProvider)
      ..invalidate(incomingRequestsProvider)
      ..invalidate(notificationsProvider);
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(message(e))));
    return false;
  }
}

/// A renter's request: where it stands and, once the owner approves, their
/// number with WhatsApp and call buttons. Used on the listing and in Bookings.
class RenterRequestCard extends ConsumerWidget {
  const RenterRequestCard({super.key, required this.request, this.showListing = true});
  final BookingRequest request;

  /// The listing's photo and title on top, for the Bookings list.
  final bool showListing;

  String _body(BuildContext context) {
    final t = context.l10n;
    final r = request;
    return switch (r.status) {
      BookingStatus.pending => t.bookingPendingBody,
      BookingStatus.approved => t.bookingApprovedBody,
      BookingStatus.confirmed => t.bookingConfirmedBody,
      BookingStatus.rejected =>
        r.datesTaken
            ? t.bookingDatesTakenBody
            : [t.bookingRejectedBody, if ((r.responseNote ?? '').isNotEmpty) '“${r.responseNote}”'].join(' '),
      BookingStatus.cancelled => r.cancelledBy == 'owner' ? t.bookingCancelledByOwner : t.bookingCancelledByYou,
    };
  }

  Future<void> _whatsapp(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final lang = context.lang;
    final r = request;
    final target = Phone.whatsappTarget(r.ownerPhone);
    if (target == null) return;
    final meta = ref.read(currentUserProvider)?.userMetadata;
    final text = t.bookingWhatsAppText(
      (meta?['full_name'] as String?)?.trim() ?? '',
      r.title(lang) ?? '',
      Fmt.night(r.checkIn, lang: lang),
      Fmt.night(r.checkOut, lang: lang),
      t.dailyNights(r.nights),
      t.dailyGuests(r.guests),
    );
    await launchUrl(Uri.https('wa.me', '/$target', {'text': text}), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final r = request;
    final tone = bookingTone(context, r);
    final phone = Phone.dialable(r.ownerPhone);
    final cancellable = r.isOpen || r.status == BookingStatus.confirmed;
    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showListing)
            InkWell(
              onTap: () => context.push(Routes.property(r.propertyId)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: Radii.chip,
                      child: SizedBox(width: 56, height: 44, child: ListingImage(url: r.coverUrl)),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: UserText(
                        r.title(lang) ?? t.inquiryDeletedProperty,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The state beside the dates, or under them when there is
                // not room for both on one line.
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_dates(r, lang), style: context.text.titleSmall),
                    _Pill(label: tone.label, color: tone.color),
                  ],
                ),
                const SizedBox(height: Space.hair),
                Text(_facts(context, r), style: context.text.bodySmall),
                const SizedBox(height: Space.xs),
                Text(_body(context), style: context.text.bodyMedium?.copyWith(color: c.inkMuted)),
                if (r.phoneShown) ...[
                  const SizedBox(height: Space.sm),
                  Text(r.ownerPhone!, textDirection: TextDirection.ltr, style: context.text.titleLarge),
                  const SizedBox(height: Space.xs),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      if (Phone.whatsappTarget(r.ownerPhone) != null)
                        FilledButton.icon(
                          onPressed: () => _whatsapp(context, ref),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855)),
                          icon: const Icon(Icons.chat_rounded, size: 18),
                          label: Text(t.bookingWhatsApp),
                        ),
                      if (phone != null)
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                          icon: const Icon(Icons.call_rounded, size: 18),
                          label: Text(t.detailsCall),
                        ),
                    ],
                  ),
                ],
                if (cancellable) ...[
                  const SizedBox(height: Space.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () async {
                        final ok = await confirmAction(
                          context,
                          title: t.bookingCancelTitle,
                          body: t.bookingCancelBody,
                          confirmLabel: t.bookingCancel,
                          cancelLabel: t.bookingKeep,
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        await _act(
                          context,
                          ref,
                          () => ref.read(dailyRepositoryProvider).respond(r.id, BookingAction.cancel),
                        );
                      },
                      child: Text(t.bookingCancel, style: TextStyle(color: c.danger)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A request for one of the owner's places, with the owner's answers.
class OwnerRequestCard extends ConsumerWidget {
  const OwnerRequestCard({super.key, required this.request});
  final BookingRequest request;

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final r = request;
    final suggested = await ref.read(dailyRepositoryProvider).lastSharedPhone();
    if (!context.mounted) return;
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => _PhoneDialog(initial: suggested, guest: r.renterName.isEmpty ? t.notifGuest : r.renterName),
    );
    if (phone == null || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(dailyRepositoryProvider).respond(r.id, BookingAction.approve, phone: phone),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(title: t.bookingRejectTitle, label: t.bookingRejectNote, action: t.bookingReject),
    );
    if (note == null || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(dailyRepositoryProvider)
          .respond(request.id, BookingAction.reject, note: note.trim().isEmpty ? null : note.trim()),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final ok = await confirmAction(
      context,
      title: t.bookingConfirmTitle,
      body: t.bookingConfirmBody,
      confirmLabel: t.bookingConfirm,
      cancelLabel: t.actionCancel,
    );
    if (!ok || !context.mounted) return;
    await _act(context, ref, () => ref.read(dailyRepositoryProvider).respond(request.id, BookingAction.confirm));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final ok = await confirmAction(
      context,
      title: t.bookingOwnerCancel,
      body: t.bookingOwnerCancelBody,
      confirmLabel: t.bookingOwnerCancel,
      cancelLabel: t.bookingKeep,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _act(context, ref, () => ref.read(dailyRepositoryProvider).respond(request.id, BookingAction.cancel));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final r = request;
    final tone = bookingTone(context, r);
    final open = r.status == BookingStatus.pending && !r.expiredOn(DateTime.now());
    final who = r.renterName.trim().isEmpty ? t.notifGuest : r.renterName.trim();
    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color.alphaBlend(c.emerald.withValues(alpha: 0.14), c.surface),
                child: Text(
                  who.characters.first.toUpperCase(),
                  style: context.text.titleSmall?.copyWith(color: c.forest),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    UserText(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                    _Pill(label: tone.label, color: tone.color),
                  ],
                ),
              ),
            ],
          ),
          InkWell(
            onTap: () => context.push(Routes.property(r.propertyId)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Text(
                t.inquiryAbout(r.title(lang) ?? t.inquiryDeletedProperty),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(color: c.emerald),
              ),
            ),
          ),
          Text(_dates(r, lang), style: context.text.titleSmall),
          const SizedBox(height: Space.hair),
          Text(_facts(context, r), style: context.text.bodySmall),
          if ((r.message ?? '').isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            UserText('“${r.message}”', style: context.text.bodyMedium),
          ],
          if (r.datesTaken) ...[
            const SizedBox(height: Space.xs),
            Text(t.bookingAutoClosed, style: context.text.bodySmall),
          ],
          if (r.phoneShown) ...[
            const SizedBox(height: Space.xs),
            Text(t.bookingSharedPhone(r.ownerPhone!), style: context.text.bodySmall?.copyWith(color: c.emerald)),
          ],
          if (open || r.status == BookingStatus.approved || r.status == BookingStatus.confirmed) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                if (open) ...[
                  FilledButton.icon(
                    onPressed: () => _approve(context, ref),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(t.bookingApprove),
                  ),
                  OutlinedButton(onPressed: () => _reject(context, ref), child: Text(t.bookingReject)),
                ],
                if (r.status == BookingStatus.approved)
                  FilledButton.icon(
                    onPressed: () => _confirm(context, ref),
                    icon: const Icon(Icons.event_available_rounded, size: 18),
                    label: Text(t.bookingConfirm),
                  ),
                if (r.status == BookingStatus.approved || r.status == BookingStatus.confirmed)
                  TextButton(
                    onPressed: () => _cancel(context, ref),
                    child: Text(t.bookingOwnerCancel, style: TextStyle(color: c.danger)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: Radii.chip),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.type.pill.copyWith(color: color),
    ),
  );
}

/// Approving: the number this guest will see, prefilled with the last one
/// the owner shared.
class _PhoneDialog extends StatefulWidget {
  const _PhoneDialog({required this.initial, required this.guest});
  final String initial;
  final String guest;

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (Phone.dialable(_c.text) == null) {
      setState(() => _error = context.l10n.validationPhone);
      return;
    }
    Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return AlertDialog(
      title: Text(t.bookingApproveTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.bookingApproveBody(widget.guest)),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            autofillHints: const [AutofillHints.telephoneNumber],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: t.bookingPhoneLabel, hintText: '07X XXX XXXX', errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.actionCancel)),
        FilledButton(onPressed: _submit, child: Text(t.bookingApprove)),
      ],
    );
  }
}

/// Declining: an optional reason the guest will read.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.label, required this.action});
  final String title;
  final String label;
  final String action;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: widget.label, alignLabelWithHint: true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.actionCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: Text(widget.action)),
      ],
    );
  }
}
