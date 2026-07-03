import 'package:flutter/material.dart';
import 'package:mangayomi/utils/platform_utils.dart';

class LoadingIcon extends StatelessWidget {
  const LoadingIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          // TV shows a dedicated (full-colour) icon; phones/desktop keep the
          // tinted default. See isTv.
          isTv
              ? "assets/app_icons/icon_red_tv.png"
              : "assets/app_icons/icon.png",
          color: isTv ? null : Colors.black,
          fit: BoxFit.cover,
          height: 100,
        ),
      ),
    );
  }
}
