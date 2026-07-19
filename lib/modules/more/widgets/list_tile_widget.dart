import 'package:flutter/material.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';

class ListTileWidget extends StatelessWidget {
  final VoidCallback onTap;
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;

  /// Claim focus on first build. Set on the first row of a pushed menu (the
  /// settings hub, etc.) so the remote has a starting point instead of being
  /// stranded on a screen with no established focus.
  final bool autofocus;
  const ListTileWidget({
    super.key,
    required this.onTap,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      autofocus: autofocus,
      onTap: onTap,
      // subtitle: subtitle != null
      //     ? Text(
      //         subtitle!,
      //         style: TextStyle(fontSize: 11, color: context.secondaryColor),
      //       )
      //     : null,
      leading: SizedBox(
        height: 40,
        child: Icon(icon, color: context.primaryColor),
      ),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: context.secondaryColor),
            )
          : null,
      trailing: trailing,
    );
  }
}
