import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/subscription_providers.dart';

/// Reached two ways: voluntarily (a "Manage subscription" link, any
/// time) or by force once app_router's redirect sees
/// gym.subscriptionBlocked (no dismiss, no way around it). Same screen
/// either way; only the body changes.
///
/// Manual-payment model: the owner pays outside the app (GCash, bank
/// transfer, etc.) and messages the operator, who marks the gym active
/// in Django admin. This screen only displays price + contact info —
/// it never sends money and there is no checkout to return from. The
/// "Refresh" button re-fetches /auth/me/ so a just-marked-active gym
/// updates without the owner needing to log out and back in.
class SubscribeScreen extends ConsumerStatefulWidget {
  const SubscribeScreen({super.key});

  @override
  ConsumerState<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends ConsumerState<SubscribeScreen> {
  bool _refreshingSession = false;

  Future<void> _refreshSession() async {
    if (_refreshingSession) return;
    setState(() => _refreshingSession = true);
    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);
      if (mounted && !(updatedUser.gym?.subscriptionBlocked ?? true)) {
        context.go('/home');
        return;
      }
    } catch (_) {
      // Offline or transient — the user can retry with the button below,
      // or app_router will pick it up next time this screen refreshes.
    } finally {
      if (mounted) setState(() => _refreshingSession = false);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatPesos(int centavos) =>
      '₱${(centavos / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(gymBillingStateProvider);

    if (billing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final blocked = billing.isBlocked;
    final days = billing.daysRemaining;
    final state = billing.billingState;

    final title = switch (state) {
      'trial_expired' => 'Your free trial has ended',
      'expired' => 'Your subscription has ended',
      'trial_expiring' =>
        '${days ?? 0} day${days == 1 ? '' : 's'} left in your trial',
      'active_expiring' =>
        '${days ?? 0} day${days == 1 ? '' : 's'} left on your subscription',
      'trial_active' => "You're on a free trial",
      'active' =>
        billing.currentPeriodEnd != null
            ? 'Active until ${_formatDate(billing.currentPeriodEnd!)}'
            : "You're subscribed",
      'canceled' => 'Your subscription was canceled',
      _ => 'Subscription',
    };

    final subtitle = blocked
        ? 'Pay using the details below, then message us to reactivate. '
              'Your members can still check in and view their own info in '
              'the meantime.'
        : 'Pay any time using the details below to keep FlexDesk running '
              'without interruption.';

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: blocked
          ? null
          : AppBar(
              backgroundColor: AppColors.pageBg,
              title: const Text('Subscription'),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                blocked ? Icons.lock_outline : Icons.timer_outlined,
                size: 56,
                color: blocked ? AppColors.errorText : AppColors.accentTeal,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.subtle),
              ),
              const SizedBox(height: 28),
              _PaymentInfoCard(formatPesos: _formatPesos),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _refreshingSession ? null : _refreshSession,
                child: _refreshingSession
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("I've paid — refresh status"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentInfoCard extends ConsumerWidget {
  const _PaymentInfoCard({required this.formatPesos});

  final String Function(int) formatPesos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentInfo = ref.watch(paymentInfoProvider);

    return paymentInfo.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Text(
        "Couldn't load payment details — check your connection and try "
        'again.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.errorText, fontSize: 13),
      ),
      data: (info) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _PriceTile(
                    label: 'Monthly',
                    price: formatPesos(info.priceMonthlyCentavos),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PriceTile(
                    label: 'Yearly',
                    price: formatPesos(info.priceYearlyCentavos),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'How to pay',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              info.paymentInstructions.isEmpty
                  ? 'Payment details coming soon.'
                  : info.paymentInstructions,
              style: const TextStyle(fontSize: 14, color: AppColors.subtle),
            ),
            const SizedBox(height: 16),
            const Text(
              'After you pay',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              info.contactInfo.isEmpty
                  ? 'Contact details coming soon.'
                  : info.contactInfo,
              style: const TextStyle(fontSize: 14, color: AppColors.subtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({required this.label, required this.price});

  final String label;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.accentTealBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            price,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.accentTeal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.subtle),
          ),
        ],
      ),
    );
  }
}
