import 'package:flutter/material.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';

/// A tappable wrapper that draws a primary-colour focus ring when it receives
/// focus via keyboard / d-pad navigation (`FocusHighlightMode.traditional`) —
/// the same focus affordance the library cover cards use (see
/// `CoverViewWidget`). On touch input no ring is ever shown.
///
/// Built for Android TV / remote navigation, where the framework's default
/// focus highlight on controls like [NavigationRail] is too faint to see from
/// across a room, but it works for hardware-keyboard users on any platform too.
/// Because the wrapped child is a real focusable [InkWell], directional (d-pad)
/// focus traversal can move in and out of it like any other focusable widget.
class FocusHighlight extends StatefulWidget {
  const FocusHighlight({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final bool autofocus;

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Drop the ring immediately if the user switches to touch input while this
    // is focused — it must never show for touch, not only when focus is lost.
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (mode != FocusHighlightMode.traditional && _focused) {
      setState(() => _focused = false);
    }
  }

  void _onFocusChange(bool hasFocus) {
    final show =
        hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (mounted && show != _focused) {
      setState(() => _focused = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Outer radius = inner clip radius + border width so the ring's corners
    // stay concentric with the child (matches CoverViewWidget).
    final outerRadius = BorderRadius.all(
      Radius.circular(widget.borderRadius.topLeft.x + 3),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        border: Border.all(
          color: _focused ? context.primaryColor : Colors.transparent,
          width: 3,
        ),
      ),
      child: Material(
        borderRadius: widget.borderRadius,
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFocusChange: _onFocusChange,
          borderRadius: widget.borderRadius,
          child: widget.child,
        ),
      ),
    );
  }
}
