import 'package:flutter/material.dart';

/// The real FlexDesk mark (assets/images/logo.png), used at the top of
/// every pre-login screen. The asset already bakes in its own light
/// mint backdrop and rounded corners, so on a white page it needs no
/// extra container the way about_credits_screen's banner usage does
/// (that screen sits on a solid teal background, which the logo's own
/// backdrop would clash with — white has no such clash).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 84});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
