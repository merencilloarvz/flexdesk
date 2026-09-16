import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_client.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/subscription_api.dart';
import '../data/subscription_models.dart';

final subscriptionApiProvider = Provider<SubscriptionApi>(
  (ref) => SubscriptionApi(ref.watch(dioProvider)),
);

/// Full subscription detail (status, both trial and paid-period dates,
/// billing_state) straight from GET /subscription/. Prefer
/// [gymBillingStateProvider] below for a banner that must render
/// immediately from the already-cached session — this one is a network
/// call, for a dedicated subscription/payment screen that wants the
/// complete picture.
final subscriptionStatusProvider = FutureProvider.autoDispose<SubscriptionStatus>(
  (ref) => ref.watch(subscriptionApiProvider).fetchStatus(),
);

/// Price + contact info for the manual-payment flow. Fetch this when
/// showing the "how to pay" screen or an expiring/expired banner's
/// contact details.
final paymentInfoProvider = FutureProvider.autoDispose<PaymentInfo>(
  (ref) => ref.watch(subscriptionApiProvider).fetchPaymentInfo(),
);

/// Lightweight billing snapshot derived from the already-loaded auth
/// session (GET /auth/me/ embeds billing_state/days_remaining on the
/// gym payload — see MeSerializer.get_gym on the backend). Use this for
/// a dashboard banner: it renders instantly on every screen that already
/// watches auth state, no extra request, and updates on the same cadence
/// app_router's own subscriptionBlocked redirect does.
class GymBillingState {
  final String? billingState;
  final int? daysRemaining;
  final DateTime? currentPeriodEnd;
  final bool isBlocked;

  const GymBillingState({
    required this.billingState,
    required this.daysRemaining,
    required this.currentPeriodEnd,
    required this.isBlocked,
  });
}

final gymBillingStateProvider = Provider.autoDispose<GymBillingState?>((ref) {
  final authState = ref.watch(authControllerProvider);
  if (authState is! AuthAuthenticated) return null;
  final gym = authState.user.gym;
  if (gym == null) return null;
  return GymBillingState(
    billingState: gym.billingState,
    daysRemaining: gym.daysRemaining,
    currentPeriodEnd: gym.currentPeriodEnd,
    isBlocked: gym.subscriptionBlocked,
  );
});
