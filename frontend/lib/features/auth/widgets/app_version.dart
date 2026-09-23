import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the real installed version (versionName on Android — the
/// pubspec `version:` field's part before the `+`) instead of a
/// hardcoded string that silently goes stale. Package-level so every
/// screen that shows a version reads the same value.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}';
});

/// Shows nothing while loading or on error rather than a placeholder —
/// a missing version string is far less confusing than a wrong one, and
/// this always resolves near-instantly since it reads local package
/// metadata, not a network call.
class AppVersionText extends ConsumerWidget {
  const AppVersionText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).asData?.value;
    if (version == null) return const SizedBox.shrink();
    return Text(
      version,
      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
    );
  }
}
