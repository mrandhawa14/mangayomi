import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangayomi/modules/widgets/tv_pill.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';

/// A focusable button used inside the TV list rows (the Browse source and
/// extension rows): transparent when idle, accent-tinted when focused, and
/// firing [onTap] on a remote OK press. Scrolls itself into view on focus.
class TvRowButton extends StatefulWidget {
  const TvRowButton({
    super.key,
    required this.onTap,
    required this.child,
    this.focusNode,
  });
  final VoidCallback onTap;
  final Widget child;
  final FocusNode? focusNode;

  @override
  State<TvRowButton> createState() => _TvRowButtonState();
}

class _TvRowButtonState extends State<TvRowButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.primaryColor;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f && context.mounted && Scrollable.maybeOf(context) != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && tvIsSelectKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _focused ? accent.withValues(alpha: 0.20) : Colors.transparent,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
