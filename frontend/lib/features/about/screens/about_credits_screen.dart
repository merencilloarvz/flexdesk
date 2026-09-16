import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Reachable in one tap from member Settings and owner Settings.
///
/// This screen exists because of the workout-guide illustrations: they're
/// CC BY-SA 4.0, and the "BY" clause requires attribution to be visible to
/// people using the app, not just noted in a README.
class AboutCreditsScreen extends StatelessWidget {
  const AboutCreditsScreen({super.key, this.appVersion = '1.0.0'});

  /// Pass your existing version string in from wherever FlexDesk already
  /// tracks it (a constant, build config, etc). Left null shows nothing.
  final String? appVersion;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            width: double.infinity,
            color: AppColors.accentTeal,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'FlexDesk',
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (appVersion != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Version $appVersion',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.fieldBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exercise illustration credit',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.grey,
                    ),
                    children: [
                      const TextSpan(text: 'Exercise illustrations by '),
                      TextSpan(
                        text: 'Bryl Lim',
                        style: TextStyle(
                          color: AppColors.accentTeal,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const TextSpan(text: ', based on artwork by '),
                      TextSpan(
                        text: 'Everkinetic',
                        style: TextStyle(
                          color: AppColors.accentTeal,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const TextSpan(text: ', licensed under CC BY-SA 4.0.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
