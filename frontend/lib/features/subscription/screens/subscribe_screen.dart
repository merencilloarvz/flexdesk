import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/subscription_providers.dart';

/// Reached two ways: voluntarily (a "Manage subscription" link, while
/// still trialing — informational, dismissible) or by force once
/// app_router's redirect sees gym.subscriptionBlocked (no dismiss, no
/// way around it). Same screen either way; only the body changes.
///
/// After returning from PayMongo's checkout page, this refetches
/// /auth/me/ the same way the first-run pricing screen does for
/// needs_setup (see ManagePlansScreen.firstRun), so app_router picks
/// up the new subscription status immediately rather
/// than waiting for the next natural refresh. Triggered both by the app
/// resuming (the user switched back from the browser) and by an
/// explicit "I've subscribed" retry, since app-resume isn't reliable on
/// every platform right after an external browser hand-off.
class SubscribeScreen extends ConsumerStatefulWidget {
  const SubscribeScreen({super.key});

  @override
  ConsumerState<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends ConsumerState<SubscribeScreen>
    with WidgetsBindingObserver {
  bool _startingCheckout = false;
  bool _refreshingSession = false;
  bool _awaitingReturn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _refreshSession();
    }
  }

  Future<void> _refreshSession() async {
    if (_refreshingSession) return;
    setState(() => _refreshingSession = true);
    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);
      _awaitingReturn = false;
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

  Future<void> _startCheckout() async {
    setState(() {
      _startingCheckout = true;
      _error = null;
    });
    try {
      final url = await ref
          .read(subscriptionApiProvider)
          .createCheckoutSession();
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened) _awaitingReturn = true;
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not start checkout. Please try again.');
    } finally {
      if (mounted) setState(() => _startingCheckout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final gym = authState is AuthAuthenticated ? authState.user.gym : null;

    if (gym == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final blocked = gym.subscriptionBlocked;
    final daysRemaining = gym.trialEndsAt?.difference(DateTime.now()).inDays;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: blocked
          ? null
          : AppBar(
              backgroundColor: AppColors.pageBg,
              title: const Text('Subscription'),
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                blocked ? Icons.lock_outline : Icons.timer_outlined,
                size: 56,
                color: blocked ? AppColors.errorText : AppColors.accentTeal,
              ),
              const SizedBox(height: 20),
              Text(
                blocked
                    ? 'Subscribe to continue'
                    : (daysRemaining != null && daysRemaining >= 0
                          ? '$daysRemaining day${daysRemaining == 1 ? '' : 's'} left in your trial'
                          : 'You\'re on a free trial'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                blocked
                    ? 'Your free trial has ended. Subscribe to keep using '
                          'FlexDesk — your members can still check in and '
                          'view their own info in the meantime.'
                    : 'Subscribe any time to keep FlexDesk running '
                          'without interruption once your trial ends.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.subtle),
              ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.errorText,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_awaitingReturn) ...[
                Text(
                  'Waiting for you to finish checkout…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.subtle,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _refreshingSession ? null : _refreshSession,
                  child: _refreshingSession
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("I've finished subscribing"),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton(
                onPressed: _startingCheckout ? null : _startCheckout,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _startingCheckout
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Subscribe now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
