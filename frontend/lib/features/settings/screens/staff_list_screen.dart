import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/staff_models.dart';
import '../providers/staff_providers.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  // Staff profile ids with a deactivate request in flight, so a second
  // tap can't fire a second request.
  final Set<String> _deactivating = {};

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final authState = ref.watch(authControllerProvider);
    final myEmail = authState is AuthAuthenticated ? authState.user.email : '';

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('Staff'),
        backgroundColor: AppColors.pageBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: _friendlyMessage(error),
          onRetry: () => ref.invalidate(staffListProvider),
        ),
        data: (staffList) {
          if (staffList.isEmpty) {
            return _EmptyState(onAdd: _openCreate);
          }

          // Owners first, then active staff, then deactivated — stable
          // within each group, so the server's order is otherwise kept.
          int rank(StaffMember s) => !s.isActive
              ? 2
              : s.role == UserRole.owner
              ? 0
              : 1;
          final sorted = [...staffList]
            ..sort((a, b) => rank(a).compareTo(rank(b)));

          return RefreshIndicator(
            color: AppColors.accentTeal,
            onRefresh: () async {
              ref.invalidate(staffListProvider);
              await ref.read(staffListProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              // Bottom room so the last row clears the floating button.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final staff = sorted[index];
                final isMe = staff.email.toLowerCase() == myEmail.toLowerCase();
                return _StaffRow(
                  staff: staff,
                  isMe: isMe,
                  busy: _deactivating.contains(staff.id),
                  onDeactivate: () => _confirmDeactivate(staff),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppColors.accentTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add staff'),
      ),
    );
  }

  void _openCreate() => context.push('/settings/staff/create');

  String _friendlyMessage(Object error) {
    if (error is ApiException) {
      switch (error.kind) {
        case ApiExceptionKind.network:
          return 'Staff management needs a connection.';
        case ApiExceptionKind.forbidden:
          return 'Only the gym owner can manage staff.';
        default:
          break;
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'Staff management needs a connection.';
    }
    return 'Something went wrong loading staff.';
  }

  Future<void> _confirmDeactivate(StaffMember staff) async {
    if (_deactivating.contains(staff.id)) return;

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

    if (confirmed != true || !mounted) return;

    setState(() => _deactivating.add(staff.id));
    try {
      await ref.read(staffRepositoryProvider).deactivateStaff(staff.id);
      ref.invalidate(staffListProvider);
    } catch (e) {
      if (!mounted) return;
      final reason = e is ApiException
          ? e.message
          : 'Please check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't deactivate: $reason")));
    } finally {
      if (mounted) setState(() => _deactivating.remove(staff.id));
    }
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.staff,
    required this.isMe,
    required this.busy,
    required this.onDeactivate,
  });

  final StaffMember staff;
  final bool isMe;
  final bool busy;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final isOwner = staff.role == UserRole.owner;
    final name = staff.fullName.trim().isEmpty ? staff.email : staff.fullName;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final canDeactivate = staff.isActive && !isMe;

    return Opacity(
      opacity: staff.isActive ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isOwner
                  ? AppColors.accentTeal
                  : AppColors.fieldBg,
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isOwner ? Colors.white : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        const _Pill(
                          label: 'You',
                          background: AppColors.accentBlueBg,
                          foreground: AppColors.accentBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    staff.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.subtle,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      isOwner
                          ? const _Pill(
                              label: 'Owner',
                              background: AppColors.accentTeal,
                              foreground: Colors.white,
                            )
                          : const _Pill(
                              label: 'Staff',
                              background: AppColors.fieldBg,
                              foreground: AppColors.ink,
                            ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          !staff.isActive
                              ? 'Deactivated — can no longer sign in'
                              : isOwner
                              ? 'Full access, including money and staff'
                              : 'Members, check-ins & POS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (canDeactivate)
              // Hidden on your own row and on rows already deactivated.
              IconButton(
                icon: const Icon(Icons.person_off_outlined),
                tooltip: 'Deactivate',
                onPressed: onDeactivate,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.accentTealBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_outlined,
                size: 30,
                color: AppColors.accentTeal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No staff yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a front-desk person to check members in and ring up '
              'sales, without giving them access to your money.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.subtle),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add staff'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
