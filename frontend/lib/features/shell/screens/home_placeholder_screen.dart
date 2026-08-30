import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_providers.dart';

class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    return Scaffold(
      appBar: AppBar(title: Text(user?.gym.name ?? 'FlexDesk')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Logged in as ${user?.role.name ?? '?'}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/members'),
              child: const Text('Members'),
            ),
          ],
        ),
      ),
    );
  }
}
