import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final email = authState is AuthAuthenticated ? authState.user.email : '';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(email),
            subtitle: const Text('Signed in'),
          ),
          const Divider(),
          if (authState is AuthAuthenticated &&
              authState.user.role == UserRole.owner) ...[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Staff'),
              subtitle: const Text('Manage staff accounts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/staff'),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log out', style: TextStyle(color: Colors.red)),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await _performLogout(context, ref, force: false);
  }

  Future<void> _performLogout(
    BuildContext context,
    WidgetRef ref, {
    required bool force,
  }) async {
    try {
      // No manual navigation needed — logout() sets AuthUnauthenticated,
      // and the router's redirect already sends that state to /login.
      await ref.read(authControllerProvider.notifier).logout(force: force);
    } on UnsyncedDataException catch (e) {
      if (!context.mounted) return;

      final proceedAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsynced records'),
          content: Text(
            '${e.count} record${e.count == 1 ? '' : 's'} '
            "haven't synced yet. Connect to wifi and try again, "
            'or log out anyway and lose that data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out anyway'),
            ),
          ],
        ),
      );

      if (proceedAnyway == true && context.mounted) {
        await _performLogout(context, ref, force: true);
      }
    }
  }
}
