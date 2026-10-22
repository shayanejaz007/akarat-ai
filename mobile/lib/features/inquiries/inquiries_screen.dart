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
import '../../core/widgets/segmented_pill.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/user_text.dart';
import '../../shared/models/account_models.dart';
import 'inquiries_providers.dart';

/// The inquiries table, read the way RLS allows: those received about your
/// listings (the website dashboard's Inquiries tab) and those you sent.
/// There is no chat backend, so this is an inbox of messages with ways to
/// reply directly — not a pretend conversation thread.
class InquiriesScreen extends ConsumerStatefulWidget {
  const InquiriesScreen({super.key, this.initialTab});
  final String? initialTab;

  @override
  ConsumerState<InquiriesScreen> createState() => _InquiriesScreenState();
}

class _InquiriesScreenState extends ConsumerState<InquiriesScreen> {
  late bool _received = widget.initialTab != 'sent';

  FutureProvider<List<Inquiry>> get _provider => _received ? receivedInquiriesProvider : sentInquiriesProvider;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final inset = Layout.inset(context);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final pillHeight = 34 * scaler.scale(1) < 40 ? 40.0 : 34 * scaler.scale(1);
    final provider = _provider;
    final async = ref.watch(provider);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight + pillHeight + Space.md,
        onRefresh: () async {
          ref.invalidate(provider);
          await ref.read(provider.future).catchError((Object _) => const <Inquiry>[]);
        },
        child: CustomScrollView(
          slivers: [
            LargeTitleBar(
              title: l.inquiriesTitle,
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(pillHeight + Space.md),
                child: Padding(
                  padding: inset.copyWith(bottom: Space.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SegmentedPill<bool>(
                      expand: !Layout.isWide(context),
                      value: _received,
                      onChanged: (v) => setState(() => _received = v),
                      segments: [
                        PillSegment(value: true, label: l.inquiriesReceived),
                        PillSegment(value: false, label: l.inquiriesSent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ...async.when(
              data: (rows) => rows.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.mark_email_read_outlined,
                          title: _received ? l.inquiriesEmpty : l.inquiriesSentEmpty,
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: inset.copyWith(top: Space.xs, bottom: Space.xxl),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                          itemBuilder: (context, i) =>
                              _InquiryCard(key: ValueKey(rows[i].id), inquiry: rows[i], received: _received),
                        ),
                      ),
                    ],
              loading: () => [
                SliverPadding(
                  padding: inset.copyWith(top: Space.xs),
                  sliver: const SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Skeleton(height: 120),
                        SizedBox(height: Space.sm),
                        Skeleton(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(error: e, onRetry: () => ref.invalidate(provider)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InquiryCard extends StatelessWidget {
  const _InquiryCard({super.key, required this.inquiry, required this.received});
  final Inquiry inquiry;
  final bool received;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final lang = context.lang;
    final q = inquiry;
    final about = q.propertyTitle(lang) ?? l.inquiryDeletedProperty;
    final from = q.name.trim().isNotEmpty ? q.name : (q.email ?? l.inquiryUnknownSender);
    final phone = Phone.dialable(q.phone);
    final email = q.email?.trim();
    final whatsapp = Phone.whatsappTarget(q.phone);
    final replies = <Widget>[
      if (email != null && email.isNotEmpty)
        _Reply(
          icon: Icons.mail_outline_rounded,
          label: l.inquiryReplyEmail,
          onTap: () => launchUrl(Uri(scheme: 'mailto', path: email, queryParameters: {'subject': about})),
        ),
      if (phone != null)
        _Reply(
          icon: Icons.call_outlined,
          label: l.inquiryReplyCall,
          onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
        ),
      if (whatsapp != null)
        _Reply(
          icon: Icons.chat_outlined,
          label: l.detailsWhatsApp,
          onTap: () => launchUrl(Uri.https('wa.me', '/$whatsapp'), mode: LaunchMode.externalApplication),
        ),
    ];
    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Color.alphaBlend(c.emerald.withValues(alpha: 0.14), c.surface),
                  child: Text(
                    from.isEmpty ? '?' : from.characters.first.toUpperCase(),
                    style: context.text.titleSmall?.copyWith(color: c.forest),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    received ? from : about,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Text(Fmt.date(q.createdAt, lang: lang), style: context.text.bodySmall),
              ],
            ),
          ),
          if (received)
            InkWell(
              onTap: () => context.push(Routes.property(q.propertyId)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
                child: Text(
                  l.inquiryAbout(about),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium?.copyWith(color: c.emerald),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.md,
              Space.xs,
              Space.md,
              replies.isEmpty || !received ? Space.md : Space.xs,
            ),
            child: UserText(q.message, style: context.text.bodyMedium),
          ),
          if (received && replies.isNotEmpty) ...[
            Divider(height: 1, color: c.border.withValues(alpha: 0.7)),
            // One line of equal replies, however many there are.
            Row(
              children: [
                for (var i = 0; i < replies.length; i++) ...[
                  if (i > 0)
                    SizedBox(height: 24, child: VerticalDivider(width: 1, color: c.border.withValues(alpha: 0.7))),
                  Expanded(child: replies[i]),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Reply extends StatelessWidget {
  const _Reply({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm + 2, horizontal: Space.xxs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: c.forest),
              const SizedBox(width: Space.iconGap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.pill.copyWith(color: c.forest),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
