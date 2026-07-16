import 'package:flutter/material.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/platform_utils.dart';

/// The retry control shown when a page image fails to load.
///
/// This is a real button rather than a bare [GestureDetector], so it can take
/// focus: with a remote there was previously no way to reach it at all, which
/// left a failed page with no way to retry. On TV it also autofocuses, since
/// it is the only action on screen, and lightens when focused so it reads
/// against its own accent fill.
class RetryButton extends StatelessWidget {
  const RetryButton({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      autofocus: isTv,
      onPressed: onRetry,
      onLongPress: onRetry,
      style:
          ElevatedButton.styleFrom(
            backgroundColor: context.primaryColor,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ).copyWith(
            // The button is already accent-filled, so focus has to read as a
            // lift against that fill rather than another accent wash.
            overlayColor: isTv
                ? WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? Colors.white.withValues(alpha: 0.30)
                        : null,
                  )
                : null,
          ),
      child: Text(context.l10n.retry),
    );
  }
}
