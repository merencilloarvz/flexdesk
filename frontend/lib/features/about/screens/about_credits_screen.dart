import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// Reachable in one tap from member Settings and owner Settings.
///
/// This screen exists because of the workout-guide illustrations: they're
/// CC BY-SA 4.0, and the "BY" clause requires attribution to be visible to
/// people using the app, not just noted in a README.
///
/// Deliberately dependency-free (no package_info_plus, no url_launcher) so
/// flutter_svg stays the only new package this feature needs. Links are
/// shown as selectable/copyable text with a tap-to-copy button instead of
/// opening a browser. If you already have url_launcher elsewhere in the
/// app, swap _CreditLink's onTap for launchUrl and drop the copy icon.
class AboutCreditsScreen extends StatelessWidget {
  const AboutCreditsScreen({super.key, this.appVersion});

  /// Pass your existing version string in from wherever FlexDesk already
  /// tracks it (a constant, build config, etc). Left null shows nothing.
  final String? appVersion;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About & credits')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('FlexDesk', style: textTheme.titleLarge),
          if (appVersion != null) ...[
            const SizedBox(height: 4),
            Text('Version $appVersion', style: textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          Text('Exercise illustration credits', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'The workout guide illustrations in this app build on the '
            'Workout Guide project by Bryl Lim, which in turn builds on '
            'the original Everkinetic pose artwork. Both are licensed '
            'under Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA '
            '4.0).',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'The SVG files are used unmodified. Any colour you see is '
            'applied at display time in the app\u2019s code \u2014 the source '
            'files themselves are untouched.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          const _CreditLink(
            label: 'License: CC BY-SA 4.0',
            url: 'https://creativecommons.org/licenses/by-sa/4.0/',
          ),
          const _CreditLink(
            label: 'Everkinetic (original pose artwork)',
            url: 'https://github.com/everkinetic/data',
          ),
          const _CreditLink(
            label: 'Bryl Lim \u2014 Workout Guide (expanded set, source repo)',
            url: 'https://github.com/bryllim/workout-guide',
          ),
        ],
      ),
    );
  }
}

class _CreditLink extends StatelessWidget {
  const _CreditLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                SelectableText(
                  url,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}
