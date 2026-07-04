import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/modules/anime/providers/auto_play_next_provider.dart';
import 'package:media_kit/media_kit.dart';

/// A dedicated, Netflix-style controls overlay for the anime player on TV.
///
/// Only the essentials are on screen — play/pause, prev/next episode, a seek
/// bar with times, and audio/subtitle access — everything else lives behind the
/// gear. Built for the d-pad: theme-coloured focus highlight on every control,
/// the seek bar seeks a small fixed amount on Left/Right and lets Up/Down move
/// focus away, and the reveal/auto-hide is driven by [revealControls] (bumped by
/// the player on each key).
class TvPlayerControls extends StatefulWidget {
  const TvPlayerControls({
    super.key,
    required this.player,
    required this.revealControls,
    required this.title,
    required this.episodeLabel,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
    required this.onBack,
    required this.onRestart,
    required this.onSettings,
    required this.onAudio,
    required this.onSubtitle,
  });

  final Player player;
  final ValueNotifier<int> revealControls;
  final String title;
  final String episodeLabel;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onBack;
  final VoidCallback onRestart;
  final VoidCallback onSettings;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  bool _visible = true;
  Timer? _hideTimer;
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'tvPlayer');
  final FocusNode _playFocus = FocusNode(debugLabel: 'tvPlayerPlayPause');
  static const _hideAfter = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    widget.revealControls.addListener(_reveal);
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.revealControls.removeListener(_reveal);
    _hideTimer?.cancel();
    _scope.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  void _reveal() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _startHideTimer();
    if (!_scope.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_playFocus.canRequestFocus ? _playFocus : _scope).requestFocus();
      });
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return FocusScope(
      node: _scope,
      // Only build the controls (and their per-frame StreamBuilders) while
      // visible. Otherwise the seek/time streams rebuild ~4x/sec during
      // playback and jank the Fire TV — hidden means nothing to render.
      child: !_visible
          ? const SizedBox.expand()
          : Stack(
              children: [
              // Scrim so white controls read over any frame.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.65),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              // Top-left: back / restart / gear.
              Positioned(
                top: 28,
                left: 28,
                child: Row(
                  children: [
                    _TvFocusable(
                      accent: accent,
                      onPressed: widget.onBack,
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    _TvFocusable(
                      accent: accent,
                      onPressed: widget.onRestart,
                      child: const Icon(
                        Icons.replay_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TvFocusable(
                      accent: accent,
                      onPressed: widget.onSettings,
                      child: const Icon(Icons.settings, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    // Autoplay-next toggle (dims when off).
                    Consumer(
                      builder: (context, ref, _) {
                        final on = ref.watch(autoPlayNextEpisodeProvider);
                        return _TvFocusable(
                          accent: accent,
                          onPressed: () => ref
                              .read(autoPlayNextEpisodeProvider.notifier)
                              .toggle(),
                          child: Icon(
                            Icons.playlist_play,
                            color: on ? Colors.white : Colors.white38,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Top-right: title + episode.
              Positioned(
                top: 28,
                right: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.title.isNotEmpty)
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (widget.episodeLabel.isNotEmpty)
                      Text(
                        widget.episodeLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              // Bottom: controls + seek + tracks.
              Positioned(
                left: 32,
                right: 32,
                bottom: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Centered play controls, on their own row so Up/Down moves
                    // focus between them, the seek bar, and the track pills.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TvFocusable(
                          accent: accent,
                          onPressed: widget.hasPrev ? widget.onPrev : null,
                          child: const Icon(
                            Icons.skip_previous,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _PlayPauseButton(
                          player: widget.player,
                          accent: accent,
                          focusNode: _playFocus,
                        ),
                        const SizedBox(width: 10),
                        _TvFocusable(
                          accent: accent,
                          onPressed: widget.hasNext ? widget.onNext : null,
                          child: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _PositionText(player: widget.player),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TvSeekBar(
                            player: widget.player,
                            accent: accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _DurationText(player: widget.player),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Inline audio + subtitle track pills (current one selected).
                    _TrackPills(player: widget.player, accent: accent),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

bool _isSelect(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA ||
    k == LogicalKeyboardKey.space;

/// A focusable control that shows a solid theme-accent background when focused
/// (clearly visible over the dark backdrop) and fires [onPressed] on select.
class _TvFocusable extends StatefulWidget {
  const _TvFocusable({
    required this.accent,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final Color accent;
  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<_TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: enabled,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _isSelect(event.logicalKey) && enabled) {
          widget.onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _focused
                ? widget.accent
                : Colors.black.withValues(alpha: 0.35),
          ),
          child: Opacity(opacity: enabled ? 1.0 : 0.4, child: widget.child),
        ),
      ),
    );
  }
}

/// The big center play/pause, focus-highlighted.
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.player,
    required this.accent,
    required this.focusNode,
  });

  final Player player;
  final Color accent;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return _TvFocusable(
          accent: accent,
          focusNode: focusNode,
          onPressed: player.playOrPause,
          child: Icon(
            playing ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 34,
          ),
        );
      },
    );
  }
}

/// Inline audio + subtitle track pills, centered. The current track in each is
/// highlighted; selecting a pill switches to it.
class _TrackPills extends StatelessWidget {
  const _TrackPills({required this.player, required this.accent});

  final Player player;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnap) {
        final tracks = tracksSnap.data ?? player.state.tracks;
        return StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (context, trackSnap) {
            final current = trackSnap.data ?? player.state.track;
            final audios = tracks.audio
                .where((t) => t.id != 'auto' && t.id != 'no')
                .toList();
            final subs = tracks.subtitle
                .where((t) => t.id != 'auto')
                .toList();
            final pills = <Widget>[
              for (final a in audios)
                _TrackPill(
                  accent: accent,
                  icon: Icons.audiotrack,
                  label: _trackLabel(a.title, a.language, a.id),
                  selected: a.id == current.audio.id,
                  onTap: () => player.setAudioTrack(a),
                ),
              for (final s in subs)
                _TrackPill(
                  accent: accent,
                  icon: Icons.subtitles_outlined,
                  label: s.id == 'no'
                      ? 'No subs'
                      : _trackLabel(s.title, s.language, s.id),
                  selected: s.id == current.subtitle.id,
                  onTap: () => player.setSubtitleTrack(s),
                ),
            ];
            if (pills.isEmpty) return const SizedBox.shrink();
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: pills,
            );
          },
        );
      },
    );
  }
}

String _trackLabel(String? title, String? language, String id) {
  final t = (title ?? '').trim();
  if (t.isNotEmpty) return t;
  final l = (language ?? '').trim();
  if (l.isNotEmpty) return l;
  return id;
}

/// A small focusable track pill: accent when focused, faded accent when it's the
/// current track (with a check), else a translucent fill.
class _TrackPill extends StatefulWidget {
  const _TrackPill({
    required this.accent,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color accent;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TrackPill> createState() => _TrackPillState();
}

class _TrackPillState extends State<_TrackPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = _focused
        ? widget.accent
        : widget.selected
        ? widget.accent.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.15);
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _isSelect(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: bg,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selected ? Icons.check : widget.icon,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A focusable seek bar: Left/Right seek a small fixed amount; Up/Down escape.
class _TvSeekBar extends StatefulWidget {
  const _TvSeekBar({required this.player, required this.accent});

  final Player player;
  final Color accent;

  @override
  State<_TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<_TvSeekBar> {
  bool _focused = false;
  static const _step = Duration(seconds: 10);

  void _seek(Duration delta) {
    var target = widget.player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final dur = widget.player.state.duration;
    if (dur > Duration.zero && target > dur) target = dur;
    widget.player.seek(target);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final k = event.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft) {
            _seek(-_step);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            _seek(_step);
            return KeyEventResult.handled;
          }
          // Up / Down / Select fall through so focus can leave the bar.
        }
        return KeyEventResult.ignored;
      },
      child: StreamBuilder<Duration>(
        stream: widget.player.stream.position,
        initialData: widget.player.state.position,
        builder: (context, snapshot) {
          final pos = snapshot.data ?? Duration.zero;
          final dur = widget.player.state.duration;
          final frac = dur.inMilliseconds > 0
              ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
              : 0.0;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: _focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.accent, width: 2),
                  )
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: _focused ? 6 : 4,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(widget.accent),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

class _PositionText extends StatelessWidget {
  const _PositionText({required this.player});
  final Player player;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snapshot) => Text(
        _fmt(snapshot.data ?? Duration.zero),
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _DurationText extends StatelessWidget {
  const _DurationText({required this.player});
  final Player player;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, snapshot) => Text(
        _fmt(snapshot.data ?? Duration.zero),
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
  }
}
