import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/localization/l10n.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/segmented_pill.dart';
import '../domain/query_parser.dart';
import '../presentation/constraint_chips.dart';
import 'speech_service.dart';

/// Opens the voice search sheet. Resolves to the request to search for, ''
/// when the reader chose to type instead, or null when they cancelled.
Future<String?> showVoiceSearch(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const VoiceSearchSheet(),
  );
}

enum _Phase { starting, listening, review, failed }

class VoiceSearchSheet extends ConsumerStatefulWidget {
  const VoiceSearchSheet({super.key});

  @override
  ConsumerState<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends ConsumerState<VoiceSearchSheet> {
  static const _bars = 28;

  late SpeechService _speech;
  _Phase _phase = _Phase.starting;
  SpeechFailure? _failure;
  bool _noLanguage = false;
  String? _langOrNull;
  String get _lang => _langOrNull ?? 'en';
  set _lang(String v) => _langOrNull = v;
  String _words = '';
  final _edit = TextEditingController();
  final List<double> _levels = List.filled(_bars, 0);
  double _level = 0;
  double _min = double.infinity;
  double _max = double.negativeInfinity;
  int _session = 0;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen in the interface's language to begin with.
    _langOrNull ??= context.lang;
  }

  @override
  void dispose() {
    _session++;
    unawaited(_speech.cancel());
    _edit.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final session = ++_session;
    setState(() {
      _phase = _Phase.starting;
      _failure = null;
      _noLanguage = false;
      _words = '';
      _levels.fillRange(0, _bars, 0);
      _level = 0;
      _min = double.infinity;
      _max = double.negativeInfinity;
    });
    final ready = await _speech.prepare();
    if (!mounted || session != _session) return;
    if (!ready) return _fail(_speech.lastFailure ?? SpeechFailure.unavailable);
    final locale = pickSpeechLocale(await _speech.localeIds(), _lang);
    if (!mounted || session != _session) return;
    if (locale == null) {
      setState(() => _noLanguage = true);
      return _fail(SpeechFailure.unavailable);
    }
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _phase = _Phase.listening);
    await _speech.listen(
      localeId: locale,
      onWords: (words, isFinal) {
        if (!mounted || session != _session) return;
        setState(() => _words = words);
        if (isFinal) _finish();
      },
      onLevel: (db) {
        if (!mounted || session != _session) return;
        _onLevel(db);
      },
      onFailure: (f) {
        if (!mounted || session != _session) return;
        // A pause after some words is the end of the request, not a failure.
        if (f == SpeechFailure.noSpeech && _words.trim().isNotEmpty) return _finish();
        _fail(f);
      },
      onDone: () {
        if (mounted && session == _session && _phase == _Phase.listening) _finish();
      },
    );
  }

  /// Levels arrive in platform-specific decibels; scale them by what this
  /// session has heard so the bars use their full height on any device.
  void _onLevel(double db) {
    _min = math.min(_min, db);
    _max = math.max(_max, db);
    final span = _max - _min;
    final v = span < 0.5 ? 0.0 : ((db - _min) / span).clamp(0.0, 1.0);
    setState(() {
      _level = _level * 0.55 + v * 0.45;
      // Shift the history left by one; the newest level enters on the end.
      _levels.setRange(0, _bars - 1, _levels, 1);
      _levels[_bars - 1] = _level;
    });
  }

  void _finish() {
    if (_phase != _Phase.listening) return;
    final text = _words.trim();
    if (text.isEmpty) return _fail(SpeechFailure.noSpeech);
    unawaited(HapticFeedback.lightImpact());
    _edit.text = text;
    setState(() {
      _phase = _Phase.review;
      _levels.fillRange(0, _bars, 0);
      _level = 0;
    });
  }

  void _fail(SpeechFailure f) {
    unawaited(_speech.cancel());
    setState(() {
      _phase = _Phase.failed;
      _failure = f;
      _levels.fillRange(0, _bars, 0);
      _level = 0;
    });
  }

  Future<void> _switchLanguage(String lang) async {
    if (lang == _lang) return;
    _lang = lang;
    await _speech.cancel();
    if (mounted) await _start();
  }

  void _search() {
    final text = _edit.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final listening = _phase == _Phase.listening;
    final height = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: math.min(height * 0.82, 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: SegmentedPill<String>(
                height: 36,
                value: _lang,
                onChanged: (v) => unawaited(_switchLanguage(v)),
                segments: const [
                  PillSegment(value: 'en', label: 'English'),
                  PillSegment(value: 'ar', label: 'العربية'),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.normal),
                switchInCurve: Motion.standard,
                child: KeyedSubtree(
                  key: ValueKey(_phase),
                  child: switch (_phase) {
                    _Phase.review => _review(context),
                    _Phase.failed => _failed(context),
                    _ => _listening(context),
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.md),
                child: _actions(context, listening),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listening(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final listening = _phase == _Phase.listening;
    final words = _words.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        children: [
          const Spacer(),
          Semantics(
            liveRegion: true,
            label: listening ? l.voiceListening : l.voiceStarting,
            child: VoiceOrb(level: _level, active: listening),
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            height: 56,
            child: ExcludeSemantics(
              child: VoiceWaveform(levels: _levels, active: listening),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            listening ? l.voiceListening : l.voiceStarting,
            style: context.text.titleMedium?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: Space.sm),
          AnimatedSize(
            duration: Motion.of(context, Motion.fast),
            child: words.isEmpty
                ? Text(
                    l.voiceHint,
                    textAlign: TextAlign.center,
                    style: context.text.bodyMedium?.copyWith(color: c.inkFaint),
                  )
                : Semantics(
                    liveRegion: true,
                    child: Text(
                      words,
                      textAlign: TextAlign.center,
                      textDirection: directionOf(words, Directionality.of(context)),
                      style: context.text.headlineSmall,
                    ),
                  ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _review(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final parsed = QueryParser.parse(_edit.text);
    final chips = constraintChips(context, parsed.constraints);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
      children: [
        const Center(child: VoiceOrb(level: 0, active: false, size: 64)),
        const SizedBox(height: Space.md),
        Text(l.voiceReviewTitle, textAlign: TextAlign.center, style: context.text.titleLarge),
        const SizedBox(height: Space.xxs),
        Text(l.voiceReviewBody, textAlign: TextAlign.center, style: context.text.bodySmall),
        const SizedBox(height: Space.md),
        TextField(
          controller: _edit,
          minLines: 2,
          maxLines: 5,
          maxLength: 400,
          keyboardType: TextInputType.text,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))],
          textDirection: directionOf(_edit.text, Directionality.of(context)),
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          style: context.text.bodyLarge,
          decoration: const InputDecoration(counterText: ''),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          // What will be searched: the request as the parser read it.
          Text(l.voiceUnderstood, style: context.text.labelMedium?.copyWith(color: c.inkMuted)),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final ch in chips) TagChip(label: ch.label, icon: ch.icon)],
          ),
        ],
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final (icon, text) = _noLanguage
        ? (Icons.translate_rounded, l.voiceNoArabic)
        : switch (_failure) {
            SpeechFailure.denied => (Icons.mic_off_rounded, l.voiceDenied),
            SpeechFailure.unavailable => (Icons.mic_off_rounded, l.voiceUnavailable),
            SpeechFailure.noSpeech => (Icons.hearing_disabled_rounded, l.voiceNoSpeech),
            SpeechFailure.network => (Icons.cloud_off_rounded, l.voiceNetwork),
            _ => (Icons.error_outline_rounded, l.voiceOther),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Color.alphaBlend(c.sand.withValues(alpha: 0.35), c.surface),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: c.forest),
          ),
          const SizedBox(height: Space.md),
          Semantics(
            liveRegion: true,
            child: Text(text, textAlign: TextAlign.center, style: context.text.titleMedium),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, bool listening) {
    final l = context.l10n;
    final canRetry =
        _phase == _Phase.failed &&
        !_noLanguage &&
        _failure != SpeechFailure.denied &&
        _failure != SpeechFailure.unavailable;
    return switch (_phase) {
      _Phase.review => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_start()),
              icon: const Icon(Icons.mic_none_rounded, size: 20),
              label: Text(l.voiceRetry, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: FilledButton.icon(
              onPressed: _edit.text.trim().isEmpty ? null : _search,
              icon: const Icon(Icons.search_rounded, size: 20),
              label: Text(l.voiceSearch, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
      _Phase.failed => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(l.voiceTypeInstead, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (canRetry) ...[
            const SizedBox(width: Space.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => unawaited(_start()),
                icon: const Icon(Icons.mic_none_rounded, size: 20),
                label: Text(l.voiceRetry, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ],
      ),
      _ => Row(
        children: [
          Expanded(
            child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l.actionCancel)),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: FilledButton.icon(
              onPressed: listening ? () => unawaited(_speech.stop()) : null,
              icon: const Icon(Icons.stop_rounded, size: 20),
              label: Text(l.voiceStop),
            ),
          ),
        ],
      ),
    };
  }
}

/// A soft orb in the brand's greens and gold that swells with the voice.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({super.key, required this.level, required this.active, this.size = 120});
  final double level;
  final bool active;
  final double size;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VoiceOrb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Breathes only while listening, and not at all when motion is reduced.
  void _sync() {
    final breathe = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (breathe && !_breath.isAnimating) {
      unawaited(_breath.repeat(reverse: true));
    } else if (!breathe && _breath.isAnimating) {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final b = Curves.easeInOut.transform(_breath.value);
        final swell = 1 + widget.level * 0.22 + (widget.active ? b * 0.04 : 0);
        final glow = widget.active ? 0.25 + widget.level * 0.5 : 0.15;
        return SizedBox(
          width: size * 1.6,
          height: size * 1.6,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: swell),
              duration: const Duration(milliseconds: 120),
              builder: (context, s, child) => Transform.scale(scale: s, child: child),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.35),
                    radius: 0.95,
                    colors: [Color(0xFF3DB394), Color(0xFF16836D), Color(0xFF123C34)],
                    stops: [0, 0.55, 1],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3DB394).withValues(alpha: glow),
                      blurRadius: size * (0.25 + widget.level * 0.35),
                      spreadRadius: size * 0.04 * widget.level,
                    ),
                    BoxShadow(
                      color: const Color(0xFFD9B25E).withValues(alpha: glow * 0.45),
                      blurRadius: size * 0.6,
                      offset: Offset(0, size * 0.08),
                    ),
                  ],
                ),
                child: Icon(
                  widget.active ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: size * 0.36,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The last couple of seconds of voice level, as mirrored rounded bars.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({super.key, required this.levels, required this.active});
  final List<double> levels;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      size: Size.infinite,
      painter: _WavePainter(
        levels: List.of(levels),
        colour: active ? c.emerald : c.border,
        accent: active ? c.forest : c.border,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.levels, required this.colour, required this.accent});
  final List<double> levels;
  final Color colour;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final n = levels.length;
    const gap = 4.0;
    final barWidth = math.max(2.0, (math.min(size.width, 320) - gap * (n - 1)) / n);
    final total = barWidth * n + gap * (n - 1);
    var x = (size.width - total) / 2;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final v = levels[i];
      final h = 4 + v * (size.height - 4);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + barWidth / 2, mid), width: barWidth, height: h),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, Paint()..color = Color.lerp(colour, accent, v)!.withValues(alpha: 0.35 + v * 0.65));
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
