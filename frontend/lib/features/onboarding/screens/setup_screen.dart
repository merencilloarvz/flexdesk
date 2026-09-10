import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../auth/providers/auth_providers.dart';
import '../../members/providers/plans_provider.dart';
import '../../members/screens/manage_plans_screen.dart' show openPlanForm;

/// First-run pricing setup. A fresh gym signs up with only the four
/// ₱0 seed plans (see SignupSerializer.DEFAULT_PLANS on the backend),
/// so `needs_setup` starts true. This screen is the ONLY way out of
/// it — there's no skip button, because a gym with zero real pricing
/// can't actually run: members can't be added with a plan, so nothing
/// downstream works either.
///
/// Deliberately does not navigate anywhere itself. Once a plan with a
/// real price exists, it refetches /auth/me/, pushes the result into
/// AuthController, and app_router's redirect logic (which already
/// checks user.gym.needsSetup) takes it from there.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _continuing = false;

  Future<void> _refreshSessionIfPriced(List<MembershipPlan> plans) async {
    if (_continuing) return;
    // Matches the backend's own needs_setup check exactly:
    // MembershipPlan.objects.filter(gym=g, price__gt=0).exists()
    final hasPricedPlan = plans.any((p) => p.priceCentavos > 0);
    if (!hasPricedPlan) return;

    _continuing = true;
    try {
      final updatedUser = await ref.read(authApiProvider).me();
      ref.read(authControllerProvider.notifier).applyUser(updatedUser);
    } catch (_) {
      // Offline or a transient failure — safe to just try again next
      // time the plan list changes, or when the user leaves and
      // returns to this screen.
      _continuing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final gymId = authState is AuthAuthenticated ? authState.user.gym.id : '';

    if (gymId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final plansAsync = ref.watch(allPlansProvider(gymId));

    ref.listen(allPlansProvider(gymId), (previous, next) {
      next.whenData(_refreshSessionIfPriced);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Set your pricing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Before members can join, set at least one real price. "
                "The starter plans below are all ₱0 — add one plan "
                "above ₱0 to continue.",
              ),
              const SizedBox(height: 20),
              Expanded(
                child: plansAsync.when(
                  data: (plans) {
                    if (plans.isEmpty) {
                      return const Center(
                        child: Text('No plans yet — add one below.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: plans.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final plan = plans[index];
                        final pesos = plan.priceCentavos / 100;
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            title: Text(plan.name),
                            subtitle: Text(
                              '${plan.durationValue} '
                              '${plan.durationUnit.toLowerCase()}',
                            ),
                            trailing: Text(
                              '₱${pesos.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Something went wrong: $error')),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => openPlanForm(context, gymId: gymId),
                icon: const Icon(Icons.add),
                label: const Text('Add a plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
