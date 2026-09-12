import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders one workout-guide SVG frame, tinted to the current theme.
///
/// The bundled SVGs are solid white silhouettes (fill="#fff", no stroke).
/// That reads fine on the library's dark gallery background but is
/// invisible on our light-mode surface, so we tint with a ColorFilter here.
/// The file on disk is never edited — this keeps the assets a "collection"
/// under CC BY-SA rather than a modified adaptation.
class GuideFrame extends StatelessWidget {
  const GuideFrame({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
  });

  final String assetPath;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      assetPath,
      fit: fit,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
