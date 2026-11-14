import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/localization/l10n.dart';
import '../../app/theme/tokens.dart';
import '../ai_search/voice/speaker.dart';
import '../ai_search/voice/speech_service.dart';
import '../ai_search/voice/voice_search_sheet.dart' show VoiceOrb;
import 'advisor_controller.dart';
import 'advisor_models.dart';

/// Opens the voice conversation with the advisor over the whole screen.
Future<void> showVoiceConversation(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const VoiceConversation()));

enum _Talk { starting, listening, thinking, speaking, paused }

/// Talking with the advisor: the reader speaks, a pause sends it, the answer
/// is read aloud by the phone's own voice, and the microphone opens again.
///
/// Each turn goes through [AdvisorController.send] like a typed one, so the
/// chat behind this screen holds everything said, with the listings. The
/// microphone is closed while the answer is read, so the advisor never hears
/// itself.
class VoiceConversation extends ConsumerStatefulWidget {
  const VoiceConversation({super.key});

  @override
  ConsumerState<VoiceConversation> createState() => _VoiceConversationState();
}

class _VoiceConversationState extends ConsumerState<VoiceConversation> {
  static const _ground = Color(0xFF12140E);
  static const _cream = Color(0xFFF7F2E7);

  late SpeechService _speech;
  late Speaker _speaker;
  _Talk _state = _Talk.starting;
  String? _langOrNull;
  String get _lang => _langOrNull ?? 'en';
  String _heard = '';
  String _reply = '';
  String? _note;
  double _level = 0;
  double _min = double.infinity;
  double _max = double.negativeInfinity;

  /// Bumped whenever the conversation moves on, so a late callback from an
  /// earlier turn changes nothing.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
    _speaker = ref.read(speakerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_listen());
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
    unawaited(_speaker.stop());
    super.dispose();
  }

  void _pause([String? note]) {
    _session++;
    unawaited(_speech.cancel());
    setState(() {
      _state = _Talk.paused;
      _note = note;
      _level = 0;
    });
  }

  String _failureText(SpeechFailure f) {
    final l = context.l10n;
    return switch (f) {
      SpeechFailure.denied => l.voiceDenied,
      SpeechFailure.unavailable => l.voiceUnavailable,
      SpeechFailure.network => l.voiceNetwork,
      SpeechFailure.noSpeech => l.voiceNoSpeech,
      SpeechFailure.other => l.voiceOther,
    };
  }

  Future<void> _listen() async {
    final session = ++_session;
    unawaited(_speaker.stop());
    setState(() {
      _state = _Talk.starting;
      _note = null;
      _level = 0;
      _min = double.infinity;
      _max = double.negativeInfinity;
    });
    final ready = await _speech.prepare();
    if (!mounted || session != _session) return;
    if (!ready) return _pause(_failureText(_speech.lastFailure ?? SpeechFailure.unavailable));
    final locale = pickSpeechLocale(await _speech.localeIds(), _lang);
    if (!mounted || session != _session) return;
    if (locale == null) return _pause(context.l10n.voiceNoArabic);
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _state = _Talk.listening;
      _heard = '';
    });
    await _speech.listen(
      localeId: locale,
      onWords: (words, isFinal) {
        if (!mounted || session != _session) return;
        setState(() => _heard = words);
        if (isFinal) unawaited(_ask());
      },
      onLevel: (db) {
        if (!mounted || session != _session) return;
        _min = math.min(_min, db);
        _max = math.max(_max, db);
        final span = _max - _min;
        final v = span < 0.5 ? 0.0 : ((db - _min) / span).clamp(0.0, 1.0);
        setState(() => _level = _level * 0.55 + v * 0.45);
      },
      onFailure: (f) {
        if (!mounted || session != _session) return;
        // A pause after some words is the end of the turn; silence is not a
        // fault either: the orb waits for a tap.
        if (f == SpeechFailure.noSpeech) return _heard.trim().isEmpty ? _pause() : unawaited(_ask());
        _pause(_failureText(f));
      },
      onDone: () {
        if (mounted && session == _session && _state == _Talk.listening) unawaited(_ask());
      },
    );
  }

  Future<void> _ask() async {
    if (_state != _Talk.listening) return;
    final text = _heard.trim();
    if (text.isEmpty) return _pause();
    final session = ++_session;
    final l = context.l10n;
    final uiLang = context.lang;
    unawaited(_speech.cancel());
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _state = _Talk.thinking;
      _heard = text;
      _reply = '';
      _level = 0;
    });
    final turn = await ref.read(advisorProvider.notifier).send(text, lang: uiLang, voice: true);
    // Closed, or moved on, while the advisor worked: the answer is in the
    // chat and nothing is read out.
    if (!mounted || session != _session) return;
    final shown = turn != null && turn.parts.any((p) => p is CardsPart || p is ComparePart);
    final ok = turn != null && turn.status == TurnStatus.done && turn.redacted == null && (turn.hasText || shown);
    if (!ok) return _pause(l.talkFailed);
    final written = speakable(turn.plainText, max: 4000);
    final reply = written.isEmpty ? l.talkOnScreen : written;
    setState(() {
      _state = _Talk.speaking;
      _reply = reply;
    });
    final result = await _speaker.speak(speakable(reply), lang: arabicShare(reply) > 0.3 ? 'ar' : 'en');
    if (!mounted || session != _session) return;
    switch (result) {
      case SpeakResult.spoken:
        unawaited(_listen());
      case SpeakResult.stopped:
        break;
      // Not read aloud: the answer stays on screen, and the orb waits.
      case SpeakResult.noVoice:
        _pause(l.talkNoVoice);
      case SpeakResult.failed:
        _pause(l.talkSpeakFailed);
    }
  }

  /// The orb is the one control: send now, interrupt, or start again.
  void _orb() {
    switch (_state) {
      case _Talk.listening:
        unawaited(_ask());
      case _Talk.speaking || _Talk.paused:
        unawaited(_listen());
      case _Talk.starting || _Talk.thinking:
        break;
    }
  }

  void _switchLang() {
    setState(() => _langOrNull = _lang == 'ar' ? 'en' : 'ar');
    if (_state == _Talk.listening || _state == _Talk.starting || _state == _Talk.paused) unawaited(_listen());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (title, hint, orbLabel, icon) = switch (_state) {
      _Talk.starting => (l.voiceStarting, '', l.voiceStarting, Icons.mic_none_rounded),
      _Talk.listening => (l.voiceListening, l.talkHintListening, l.talkOrbSend, Icons.mic_rounded),
      _Talk.thinking => (l.talkThinking, l.talkHintThinking, l.talkThinking, Icons.more_horiz_rounded),
      _Talk.speaking => (l.talkSpeaking, l.talkHintSpeaking, l.talkOrbInterrupt, Icons.graphic_eq_rounded),
      _Talk.paused => (l.talkPaused, '', l.talkOrbStart, Icons.mic_none_rounded),
    };
    final soft = _cream.withValues(alpha: 0.66);
    final edge = BorderSide(color: _cream.withValues(alpha: 0.24));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _ground,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -0.35), radius: 1.1, colors: [Color(0xFF1F2E25), _ground]),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.md),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Tooltip(
                            message: l.talkLangSwitch,
                            child: OutlinedButton.icon(
                              onPressed: _switchLang,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _cream,
                                backgroundColor: Colors.transparent,
                                side: edge,
                                shape: const StadiumBorder(),
                                minimumSize: const Size(0, 44),
                              ),
                              icon: const Icon(Icons.language_rounded, size: 18),
                              label: Text(
                                _lang == 'ar' ? l.talkLangAr : l.talkLangEn,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      IconButton(
                        tooltip: l.talkClose,
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          foregroundColor: _cream,
                          side: edge,
                          minimumSize: const Size(44, 44),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              button: true,
                              label: orbLabel,
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _orb,
                                child: AnimatedOpacity(
                                  opacity: _state == _Talk.paused ? 0.55 : 1,
                                  duration: Motion.normal,
                                  child: VoiceOrb(
                                    level: _state == _Talk.speaking ? 0.35 : _level,
                                    active: _state != _Talk.paused && _state != _Talk.starting,
                                    size: 148,
                                    icon: icon,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: Space.xs),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                style: context.text.titleLarge?.copyWith(color: _cream),
                              ),
                            ),
                            if (hint.isNotEmpty) ...[
                              const SizedBox(height: Space.xxs),
                              Text(
                                hint,
                                textAlign: TextAlign.center,
                                style: context.text.bodySmall?.copyWith(color: soft),
                              ),
                            ],
                            if (_note case final note?) ...[
                              const SizedBox(height: Space.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
                                decoration: BoxDecoration(
                                  color: _cream.withValues(alpha: 0.1),
                                  borderRadius: Radii.field,
                                ),
                                child: Text(
                                  note,
                                  textAlign: TextAlign.center,
                                  style: context.text.bodySmall?.copyWith(color: _cream),
                                ),
                              ),
                            ],
                            if (_heard.isNotEmpty) ...[
                              const SizedBox(height: Space.lg),
                              Text(
                                _heard,
                                textAlign: TextAlign.center,
                                style: context.text.bodyMedium?.copyWith(color: _cream.withValues(alpha: 0.6)),
                              ),
                            ],
                            if (_reply.isNotEmpty) ...[
                              const SizedBox(height: Space.sm),
                              Text(
                                _reply,
                                textAlign: TextAlign.center,
                                style: context.text.bodyLarge?.copyWith(color: _cream, height: 1.6),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Text(
                    l.talkKept,
                    textAlign: TextAlign.center,
                    style: context.text.labelSmall?.copyWith(color: _cream.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
