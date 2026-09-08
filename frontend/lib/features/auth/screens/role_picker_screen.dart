import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The very first screen an unauthenticated person sees. Deliberately
/// forces a choice before showing any form — the most likely user error
/// in the member-accounts feature is a member tapping "create account"
/// and accidentally creating an empty gym with themselves as owner. That
/// produces a dead account and a confused person, and this screen exists
/// specifically to prevent it.
class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'FlexDesk',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Who are you signing in as?',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("I'm a gym owner"),
                    ),
                    onPressed: () => context.push('/login/owner'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.fitness_center_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("I'm a gym member"),
                    ),
                    onPressed: () => context.push('/login/member'),
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
