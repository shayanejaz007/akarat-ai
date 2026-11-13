import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/layout.dart';
import 'reply_view.dart' show isArabicText;

/// Where an iPad's share popover points: the button that opened it.
Rect? shareOrigin(BuildContext button) {
  final box = button.findRenderObject();
  return box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
}

/// The message box under both assistants' conversations.
///
/// One round button does three jobs, as on the website: with nothing typed
/// it listens (voice), with text it sends, and while an answer is being
/// written it stops it. [onAttach] adds a paperclip (Ask a Lawyer). [above]
/// sits over the field: the search criteria, or the documents waiting to go
/// with the next question.
class AssistantComposer extends StatelessWidget {
  const AssistantComposer({
    super.key,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.label,
    required this.busy,
    required this.maxLength,
    required this.onSend,
    required this.onStop,
    required this.onVoice,
    this.onAttach,
    this.attachLabel,
    this.above,
    this.enabled = true,
    this.canSendEmpty = false,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final String label;
  final bool busy;
  final int maxLength;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onVoice;
  final VoidCallback? onAttach;
  final String? attachLabel;
  final Widget? above;
  final bool enabled;

  /// Sending with an empty box is allowed (a document is waiting).
  final bool canSendEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: Layout.inset(
            context,
            top: Space.sm,
            bottom: Space.sm,
          ).copyWith(left: Layout.inset(context).left - 4, right: Layout.inset(context).right - 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: Motion.of(context, Motion.fast),
                alignment: Alignment.topCenter,
                child: above == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: above,
                      ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (onAttach != null) ...[
                    _RoundButton(
                      icon: Icons.attach_file_rounded,
                      label: attachLabel ?? '',
                      onTap: enabled ? onAttach : null,
                      filled: false,
                    ),
                    const SizedBox(width: Space.xs),
                  ],
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 6,
                      maxLength: maxLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintMaxLines: 1,
                        counterText: '',
                        filled: true,
                        fillColor: c.surfaceMuted,
                        border: const OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide.none),
                        enabledBorder: const OutlineInputBorder(borderRadius: Radii.field, borderSide: BorderSide.none),
                        disabledBorder: const OutlineInputBorder(
                          borderRadius: Radii.field,
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: Radii.field,
                          borderSide: BorderSide(color: c.emerald, width: 1.4),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 13),
                      ),
                      // Screen readers hear what the box is for, not the hint.
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, v, _) {
                      final hasText = v.text.trim().isNotEmpty;
                      if (busy) {
                        return _RoundButton(icon: Icons.stop_rounded, label: l.advStop, onTap: onStop, filled: true);
                      }
                      if (hasText || canSendEmpty) {
                        return _RoundButton(
                          icon: Icons.arrow_upward_rounded,
                          label: l.advSend,
                          onTap: enabled ? onSend : null,
                          filled: true,
                        );
                      }
                      return _RoundButton(
                        icon: Icons.mic_rounded,
                        label: l.aiHubDictate,
                        onTap: enabled ? onVoice : null,
                        filled: true,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, required this.filled});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      child: Tooltip(
        message: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: filled ? (on ? c.forest : c.surfaceMuted) : c.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: filled ? (on ? c.onForest : c.inkFaint) : (on ? c.ink : c.inkFaint)),
          ),
        ),
      ),
    );
  }
}

/// "Thinking…", "Searching Akarat.ai listings…": what the assistant is doing
/// while it works, with a small spinner, read out to screen readers.
class WorkingLine extends StatelessWidget {
  const WorkingLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.emerald)),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(text, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
          ),
        ],
      ),
    );
  }
}

/// A notice under (or over) an answer: the risk note, a cut-off answer, a
/// withdrawn reply. [tone] picks the colour: info, warning or danger.
class AssistantNotice extends StatelessWidget {
  const AssistantNotice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone = NoticeTone.info,
  });
  final String text;
  final IconData icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (tone) {
      NoticeTone.info => c.inkMuted,
      NoticeTone.warning => c.warning,
      NoticeTone.danger => c.danger,
    };
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.07), c.surface),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(text, style: context.text.bodySmall?.copyWith(color: c.ink, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, danger }

/// The reader's own message, with what went with it ([footer]: the
/// documents sent to Ask a Lawyer).
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text, this.footer});
  final String text;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(Radii.md),
              topEnd: Radius.circular(Radii.md),
              bottomStart: Radius.circular(Radii.md),
              bottomEnd: Radius.circular(Radii.xs),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                text,
                textDirection: isArabicText(text) ? TextDirection.rtl : TextDirection.ltr,
                style: context.text.bodyLarge,
              ),
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// What the assistant did for an answer, in one line ([label]), opening to
/// the list of its [steps]: the searches it ran and the pages it read.
class StepsSummary extends StatefulWidget {
  const StepsSummary({super.key, required this.label, required this.steps});
  final String label;
  final List<String> steps;

  @override
  State<StepsSummary> createState() => _StepsSummaryState();
}

class _StepsSummaryState extends State<StepsSummary> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.xs),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 16, color: c.emerald),
                  const SizedBox(width: Space.iconGap),
                  Flexible(
                    child: Text(widget.label, style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
                  ),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: c.inkMuted),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 22, top: Space.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final st in widget.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xxs),
                    child: Text('• $st', style: context.text.bodySmall?.copyWith(color: c.inkMuted)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
