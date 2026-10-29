import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/state_views.dart';
import '../../shared/models/listing.dart';

/// A daily rental's review as its owner sees it: a grey check while it waits
/// (hidden from everyone else), a green one once approved, red with the
/// admins' reason when rejected or suspended.
({String label, Color color, IconData icon}) reviewTone(BuildContext context, Listing l) {
  final t = context.l10n;
  final c = context.colors;
  return switch (l.dailyReview) {
    DailyReview.approved => (label: t.reviewApproved, color: c.emerald, icon: Icons.verified_rounded),
    DailyReview.rejected => (label: t.reviewRejected, color: c.danger, icon: Icons.error_outline_rounded),
    DailyReview.suspended => (label: t.reviewSuspended, color: c.danger, icon: Icons.block_rounded),
    DailyReview.pending || null => (label: t.reviewPending, color: c.inkFaint, icon: Icons.verified_outlined),
  };
}

class DailyReviewNotice extends StatelessWidget {
  const DailyReviewNotice({super.key, required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final note = listing.dailyReviewNote?.trim() ?? '';
    final tone = reviewTone(context, listing);
    final text = switch (listing.dailyReview) {
      DailyReview.approved => tone.label,
      DailyReview.rejected => t.reviewRejectedBody(note.isEmpty ? '—' : note),
      DailyReview.suspended => t.reviewSuspendedBody(note.isEmpty ? '—' : note),
      DailyReview.pending || null => t.reviewPendingBody,
    };
    return NoticeLine(icon: tone.icon, text: text, tone: tone.color);
  }
}
