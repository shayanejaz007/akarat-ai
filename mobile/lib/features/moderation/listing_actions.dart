import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/l10n.dart';
import '../../app/router/routes.dart';
import '../../app/theme/tokens.dart';
import '../../core/config/env.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/motion.dart';
import '../../shared/models/listing.dart';
import '../../shared/repositories/reports_repository.dart';
import '../../shared/services/hidden_owners.dart';
import '../../shared/services/supabase_providers.dart';

/// A listing's "More": report it, or hide everything its advertiser posts.
/// Both app stores ask this of an app where people publish content (App
/// Store guideline 1.2, Google Play's user-generated content policy).
Future<void> showListingActions(BuildContext context, WidgetRef ref, Listing listing) async {
  final l = context.l10n;
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(l.reportListing),
            onTap: () => Navigator.pop(context, 'report'),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text(l.hideAdvertiser),
            onTap: () => Navigator.pop(context, 'hide'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'report':
      await reportListing(context, ref, listing);
    case 'hide':
      await hideAdvertiser(context, ref, listing);
  }
}

/// Reports [listing]. Signed out, the reader is asked to sign in first: a
/// report then has someone to follow up with, and cannot be sent in bulk
/// anonymously.
Future<void> reportListing(BuildContext context, WidgetRef ref, Listing listing) async {
  final l = context.l10n;
  if (ref.read(currentUserProvider) == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.reportSignIn)));
    unawaited(context.push(Routes.signIn));
    return;
  }
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReportSheet(listing: listing),
  );
  if ((sent ?? false) && context.mounted) showSuccess(context, l.reportThanks);
}

/// Hides everything [listing]'s advertiser posts, on this device, after
/// confirming. The page closes, since this listing is hidden too. Profile
/// can show them again.
Future<void> hideAdvertiser(BuildContext context, WidgetRef ref, Listing listing) async {
  final l = context.l10n;
  final ok = await confirmAction(
    context,
    title: l.hideAdvertiserTitle,
    body: l.hideAdvertiserBody,
    confirmLabel: l.hideAdvertiserAction,
    cancelLabel: l.actionCancel,
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await ref.read(hiddenOwnersProvider.notifier).hide(listing.ownerId);
  if (!context.mounted) return;
  showSuccess(context, l.hideAdvertiserDone);
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.home);
  }
}

/// Why, and a few words more if the reader wants. Before migration 0015 the
/// report goes by email instead, written out, so nothing is lost.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.listing});
  final Listing listing;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _details = TextEditingController();
  ReportReason? _reason;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _error = null);
    final l = context.l10n;
    final fallback = context.failureMessage;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final id = widget.listing.id;
    try {
      await ref.read(reportsRepositoryProvider).reportListing(id, reason, details: _details.text);
      nav.pop(true);
    } on ReportsUnavailable {
      nav.pop(false);
      messenger.showSnackBar(
        SnackBar(content: Text(l.reportByEmail(Env.supportEmail)), duration: const Duration(seconds: 6)),
      );
      await launchUrl(
        Uri(
          scheme: 'mailto',
          path: Env.supportEmail,
          queryParameters: {
            'subject': 'Listing report ${id.substring(0, 8)}',
            'body':
                '''
Listing: ${Env.listingWebUrl(id, 'en')}
Reason: ${reason.stored}

${_details.text.trim()}''',
          },
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = fallback(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final reasons = {
      ReportReason.scam: l.reportReasonScam,
      ReportReason.wrongDetails: l.reportReasonWrong,
      ReportReason.unavailable: l.reportReasonUnavailable,
      ReportReason.offensive: l.reportReasonOffensive,
      ReportReason.other: l.reportReasonOther,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.reportListing, style: context.text.titleLarge),
            const SizedBox(height: Space.xxs),
            Text(l.reportBody, style: context.text.bodySmall),
            const SizedBox(height: Space.md),
            for (final MapEntry(key: reason, value: label) in reasons.entries)
              Semantics(
                selected: _reason == reason,
                inMutuallyExclusiveGroup: true,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _reason == reason ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    color: _reason == reason ? c.emerald : c.inkFaint,
                  ),
                  title: Text(label),
                  onTap: () => setState(() => _reason = reason),
                ),
              ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: InputDecoration(labelText: l.reportDetails, alignLabelWithHint: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.xs),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: context.text.bodySmall?.copyWith(color: c.danger)),
              ),
            ],
            const SizedBox(height: Space.md),
            BusyButton(label: l.reportSend, icon: Icons.flag_outlined, onPressed: _reason == null ? null : _send),
          ],
        ),
      ),
    );
  }
}
