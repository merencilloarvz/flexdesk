import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';

class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    return Scaffold(
      appBar: AppBar(title: Text(user?.gym.name ?? 'FlexDesk')),
      body: Center(child: Text('Logged in as ${user?.role.name ?? '?'}')),
    );
  }
}
