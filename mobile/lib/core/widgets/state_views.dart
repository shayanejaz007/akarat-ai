import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../errors/app_failure.dart';
import 'motion.dart';

/// An honest empty state: says what is missing and, where there is one,
/// offers the next useful step. Never filled with invented content.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action, this.compact = false});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Reveal(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Space.xl, vertical: compact ? Space.lg : Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: Color.alphaBlend(c.sand.withValues(alpha: 0.35), c.surface),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 26 : 32, color: c.forest),
            ),
            const SizedBox(height: Space.md),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
            if (body != null) ...[
              const SizedBox(height: Space.xs),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// An error with a retry. The sentence comes from the error's kind; the raw
/// message is never shown.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final offline = AppFailure.from(error).isOffline;
    return EmptyState(
      compact: compact,
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: context.failureMessage(error),
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(context.l10n.actionRetry),
            ),
    );
  }
}

/// A one-line notice with an icon, for inline caveats ("approximate
/// location", "served directly", "saved on this device").
class NoticeLine extends StatelessWidget {
  const NoticeLine({super.key, required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = tone ?? c.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs + 2),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.08), c.surface),
        borderRadius: Radii.field,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(text, style: context.text.bodySmall?.copyWith(color: c.ink)),
          ),
        ],
      ),
    );
  }
}
