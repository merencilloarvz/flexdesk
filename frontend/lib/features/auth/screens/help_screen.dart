import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/fade_slide_in.dart';

const _supportEmail = 'flexdeskisufst@gmail.com';

/// Reached from every "Need help?" / "Contact support" / "Contact gym
/// staff" link across the pre-login screens (role picker, both login
/// variants, claim, signup). Every answer here describes how the app
/// actually behaves today — see MemberViewSet.claim_code and
/// MemberViewSet.reset_password on the backend, and ClaimScreen's own
/// doc comments — not an aspirational self-service flow that doesn't
/// exist yet.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _emailSupport(BuildContext context) async {
    try {
      await launchUrl(Uri(scheme: 'mailto', path: _supportEmail));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Email us at $_supportEmail')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(
          color: Colors.black87,
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: FadeSlideIn(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  const Center(child: AppLogo(size: 64)),
                  const SizedBox(height: 20),
                  Text(
                    'Need help?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Here are answers to the most common questions.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),

                  const _HelpItem(
                    question: 'How do I get a signup code as a member?',
                    answer:
                        'Ask staff at your gym — they can generate a '
                        'one-time code for you right in the app. They\'ll '
                        'read it out, show it to you, or let you scan a QR '
                        'code. On the "Set up your account" screen, enter '
                        'that code along with the email your gym has on '
                        'file, then choose your own password. The code '
                        'works once and expires after 30 days.',
                  ),
                  const _HelpItem(
                    question: 'I forgot my password. What do I do?',
                    answer:
                        'It depends on your account. Members: ask staff at '
                        'your gym to reset it for you — they\'ll hand you a '
                        'temporary password, and you\'ll set a new one the '
                        'moment you sign in with it. Gym owners and staff: '
                        'email us and we\'ll help you get back in.',
                  ),
                  const _HelpItem(
                    question: 'How do I know which account type I have?',
                    answer:
                        'If you run or work at a gym and use FlexDesk to '
                        'check people in, ring up sales, or manage the '
                        'gym, you\'re an owner or staff account. If you '
                        'work out at a gym that uses FlexDesk, you\'re a '
                        'member. Still not sure? Ask whoever gave you '
                        'access to the app.',
                  ),

                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.accentTealBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Still stuck?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Email us and we\'ll sort it out.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _emailSupport(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentTeal,
                              side: const BorderSide(
                                color: AppColors.accentTeal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.mail_outline, size: 18),
                            label: const Text(_supportEmail),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  const _HelpItem({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
