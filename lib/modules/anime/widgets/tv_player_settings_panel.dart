import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';

/// The YouTube-style settings panel that docks on the right of the TV player
/// while the video shrinks to the left. Reuses the player's existing
/// quality / subtitle / audio widgets for their sections and adds a d-pad
/// playback-speed row group. Back (or the close button) dismisses it.
class TvPlayerSettingsPanel extends StatefulWidget {
  const TvPlayerSettingsPanel({
    super.key,
    required this.speedListenable,
    required this.onSetSpeed,
    required this.qualityWidget,
    required this.subtitleWidget,
    required this.audioWidget,
    required this.onClose,
  });

  final ValueListenable<double> speedListenable;
  final ValueChanged<double> onSetSpeed;
  final Widget qualityWidget;
  final Widget subtitleWidget;
  final Widget audioWidget;
  final VoidCallback onClose;

  @override
  State<TvPlayerSettingsPanel> createState() => _TvPlayerSettingsPanelState();
}

class _TvPlayerSettingsPanelState extends State<TvPlayerSettingsPanel> {
  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  final _closeFocus = FocusNode(debugLabel: 'tvSettingsClose');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _closeFocus.dispose();
    super.dispose();
  }

  static String _fmtSpeed(double r) {
    final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toString();
    return '$s×';
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.34).clamp(340.0, 460.0);
    // Back closes the panel (not the player) while it's open.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: FocusTraversalGroup(
        child: Container(
          width: width,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        focusNode: _closeFocus,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section(context, 'Playback speed'),
                        _SpeedRow(
                          accent: accent,
                          speeds: _speeds,
                          speedListenable: widget.speedListenable,
                          onSetSpeed: widget.onSetSpeed,
                          fmt: _fmtSpeed,
                        ),
                        _section(context, 'Quality'),
                        widget.qualityWidget,
                        _section(context, 'Subtitles'),
                        widget.subtitleWidget,
                        _section(context, 'Audio'),
                        widget.audioWidget,
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Theme.of(context).hintColor,
      ),
    ),
  );
}

/// Horizontal, d-pad-focusable list of speed presets; the current one is filled.
class _SpeedRow extends StatelessWidget {
  const _SpeedRow({
    required this.accent,
    required this.speeds,
    required this.speedListenable,
    required this.onSetSpeed,
    required this.fmt,
  });

  final Color accent;
  final List<double> speeds;
  final ValueListenable<double> speedListenable;
  final ValueChanged<double> onSetSpeed;
  final String Function(double) fmt;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: speedListenable,
      builder: (context, rate, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            for (final s in speeds)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _SpeedChip(
                  accent: accent,
                  label: fmt(s),
                  selected: (s - rate).abs() < 0.001,
                  onTap: () => onSetSpeed(s),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpeedChip extends StatefulWidget {
  const _SpeedChip({
    required this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Color accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SpeedChip> createState() => _SpeedChipState();
}

class _SpeedChipState extends State<_SpeedChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = _focused
        ? widget.accent
        : widget.selected
        ? widget.accent.withValues(alpha: 0.22)
        : Theme.of(context).hintColor.withValues(alpha: 0.14);
    final fg = _focused
        ? Colors.white
        : widget.selected
        ? widget.accent
        : Theme.of(context).colorScheme.onSurface;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
