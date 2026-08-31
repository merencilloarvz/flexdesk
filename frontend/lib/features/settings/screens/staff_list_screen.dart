import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/staff_models.dart';
import '../providers/staff_providers.dart';

class StaffListScreen extends ConsumerWidget {
  const StaffListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);
    final authState = ref.watch(authControllerProvider);
    final myEmail = authState is AuthAuthenticated ? authState.user.email : '';

    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_friendlyMessage(error), textAlign: TextAlign.center),
          ),
        ),
        data: (staffList) {
          if (staffList.isEmpty) {
            return const Center(child: Text('No staff yet.'));
          }
          return ListView.builder(
            itemCount: staffList.length,
            itemBuilder: (context, index) {
              final staff = staffList[index];
              final isMe = staff.email.toLowerCase() == myEmail.toLowerCase();

              return Opacity(
                opacity: staff.isActive ? 1.0 : 0.5,
                child: ListTile(
                  title: Text(staff.fullName),
                  subtitle: Text(
                    staff.isActive
                        ? staff.email
                        : '${staff.email} · Deactivated',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(
                          staff.role == UserRole.owner ? 'Owner' : 'Staff',
                        ),
                      ),
                      // No deactivate control if it's inactive already,
                      // or if it's your own row (server would 400 anyway).
                      if (staff.isActive && !isMe)
                        IconButton(
                          icon: const Icon(Icons.person_off_outlined),
                          tooltip: 'Deactivate',
                          onPressed: () =>
                              _confirmDeactivate(context, ref, staff),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/settings/staff/create'),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _friendlyMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'Staff management needs a connection.';
    }
    return 'Something went wrong loading staff.';
  }

  Future<void> _confirmDeactivate(
    BuildContext context,
    WidgetRef ref,
    StaffMember staff,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate staff?'),
        content: Text(
          '${staff.fullName} will no longer be able to log in. '
          "There's no undo for this from the app.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(staffRepositoryProvider).deactivateStaff(staff.id);
      ref.invalidate(staffListProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not deactivate: $e')));
    }
  }
}
