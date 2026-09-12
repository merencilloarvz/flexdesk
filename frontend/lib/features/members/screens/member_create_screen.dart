import 'package:flexdesk/features/members/data/members_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/providers/auth_providers.dart';
import '../../dashboard/providers/analytics_providers.dart';
import '../providers/members_providers.dart';
import '../providers/plans_provider.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cFieldBg = Color(0xFFF5F6F7);
const Color _cCardBg = Colors.white;
const Color _cAccentTeal = Color(0xFF2F6FE4);
const Color _cAccentTealBg = Color(0xFFEAF1FE);
const Color _cErrorBg = Color(0xFFFCEBE8);
const Color _cErrorText = Color(0xFF9E3125);
const Color _cDisabledBg = Color(0xFFE2E5E3);
const Color _cDisabledLabel = Color(0xFF9AA39E);

class MemberCreateScreen extends ConsumerStatefulWidget {
  const MemberCreateScreen({super.key});

  @override
  ConsumerState<MemberCreateScreen> createState() => _MemberCreateScreenState();
}

class _MemberCreateScreenState extends ConsumerState<MemberCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _planId;

  bool _isSubmitting = false;
  String? _generalError;
  Map<String, List<String>>? _fieldErrors;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _errorFor(String key) {
    final errors = _fieldErrors?[key];
    return errors == null || errors.isEmpty ? null : errors.first;
  }

  (String, String) _splitName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return (first, last);
  }

  Future<void> _showAddedDialog({required bool offline}) {
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: _cAccentTealBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: _cAccentTeal, size: 26),
        ),
        title: const Text(
          'Member added',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, color: _cInk),
        ),
        content: Text(
          offline
              ? "Saved on this device — it'll sync to the server once "
                    "you're back online."
              : 'The new member has been saved.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _cMuted),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _cAccentTeal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit({
    required String gymId,
    required String homeLocationId,
  }) async {
    if (_isSubmitting) return;

    final missingFieldErrors = <String, List<String>>{};
    if (_nameCtrl.text.trim().isEmpty) {
      missingFieldErrors['first_name'] = ['Name is required.'];
    }
    if (_emailCtrl.text.trim().isEmpty) {
      missingFieldErrors['email'] = ['Email is required.'];
    }
    if (missingFieldErrors.isNotEmpty) {
      setState(() => _fieldErrors = missingFieldErrors);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _generalError = null;
      _fieldErrors = null;
    });

    final (firstName, lastName) = _splitName(_nameCtrl.text);

    final result = await ref
        .read(membersRepositoryProvider)
        .createMember(
          gymId: gymId,
          firstName: firstName,
          lastName: lastName,
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          dateOfBirth: null,
          memberType: 'MEMBER',
          notes: '',
          homeLocationId: homeLocationId,
          planId: _planId,
        );

    if (!mounted) return;

    switch (result.outcome) {
      case CreateMemberOutcome.synced:
        ref.invalidate(analyticsProvider);
        await _showAddedDialog(offline: false);
        if (mounted) context.pop();
      case CreateMemberOutcome.queuedOffline:
        await _showAddedDialog(offline: true);
        if (mounted) context.pop();
      case CreateMemberOutcome.rejected:
        setState(() {
          _isSubmitting = false;
          _fieldErrors = result.fieldErrors;
          _generalError =
              result.fieldErrors == null || result.fieldErrors!.isEmpty
              ? (result.message ?? 'Something went wrong. Please try again.')
              : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final gymId = authState.user.gym?.id ?? '';
    final homeLocationId = authState.user.defaultLocationId;
    final plansAsync = ref.watch(activePlansProvider(gymId));

    return Scaffold(
      backgroundColor: _cPageBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: _cInk),
                  ),
                  const Text(
                    'Add Member',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _cInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (homeLocationId == null) ...[
                _banner(
                  'No location assigned — ask your gym owner.',
                  bg: _cErrorBg,
                  fg: _cErrorText,
                ),
                const SizedBox(height: 16),
              ] else if (_generalError != null) ...[
                _banner(_generalError!, bg: _cErrorBg, fg: _cErrorText),
                const SizedBox(height: 16),
              ],

              _fieldCard(
                label: 'FULL NAME',
                required: true,
                hint: 'e.g. Juan Dela Cruz',
                controller: _nameCtrl,
                error: _errorFor('first_name') ?? _errorFor('last_name'),
              ),
              const SizedBox(height: 12),
              _fieldCard(
                label: 'MOBILE NUMBER',
                hint: '912 345 6789',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                error: _errorFor('phone'),
                trailing: const Text(
                  'Optional',
                  style: TextStyle(fontSize: 11, color: _cMuted),
                ),
              ),
              const SizedBox(height: 12),
              _fieldCard(
                label: 'EMAIL ADDRESS',
                hint: 'juan@example.com',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                error: _errorFor('email'),
                prefixIcon: Icons.mail_outline,
              ),
              const SizedBox(height: 12),
              _planCard(plansAsync),

              const SizedBox(height: 24),
              _saveButton(
                enabled: homeLocationId != null,
                onPressed: homeLocationId == null
                    ? null
                    : () =>
                          _submit(gymId: gymId, homeLocationId: homeLocationId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String message, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: fg, fontSize: 13)),
    );
  }

  Widget _fieldCard({
    required String label,
    required TextEditingController controller,
    bool required = false,
    String? hint,
    TextInputType? keyboardType,
    String? error,
    IconData? prefixIcon,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cCardBg,
        borderRadius: BorderRadius.circular(14),
        border: error != null ? Border.all(color: _cErrorText) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: _cSubtle,
                ),
              ),
              if (required)
                const Text(
                  ' *',
                  style: TextStyle(color: _cErrorText, fontSize: 11),
                ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: 18, color: _cMuted),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  enabled: !_isSubmitting,
                  style: const TextStyle(fontSize: 15, color: _cInk),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: _cMuted, fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: _cErrorText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planCard(AsyncValue plansAsync) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cCardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MEMBERSHIP PLAN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: _cSubtle,
                ),
              ),
              GestureDetector(
                onTap: () => context.push('/plans/manage'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Manage plans',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _cAccentTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _cFieldBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: plansAsync.when(
              data: (plans) {
                final items = <DropdownMenuItem<String?>>[
                  const DropdownMenuItem(value: null, child: Text('No plan')),
                  ...plans.map(
                    (p) => DropdownMenuItem(
                      value: p.id as String,
                      child: Text(
                        p.category.isEmpty
                            ? p.name as String
                            : '${p.name} (${p.category})',
                      ),
                    ),
                  ),
                ];
                return DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _planId,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: _cAccentTeal,
                    ),
                    items: items,
                    onChanged: _isSubmitting
                        ? null
                        : (v) => setState(() => _planId = v),
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "Couldn't load plans",
                  style: TextStyle(color: _cMuted, fontSize: 14),
                ),
              ),
            ),
          ),
          if (_planId != null)
            plansAsync.maybeWhen(
              data: (plans) {
                final selected = (plans as List).cast<dynamic>().firstWhere(
                  (p) => p.id == _planId,
                  orElse: () => null,
                );
                if (selected == null) return const SizedBox.shrink();
                final pesos = (selected.priceCentavos as int) / 100;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '₱${pesos.toStringAsFixed(2)} / ${selected.durationValue} '
                    '${(selected.durationUnit as String).toLowerCase()}'
                    '${selected.durationValue == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: _cMuted),
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _saveButton({
    required bool enabled,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: (enabled && !_isSubmitting) ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? _cAccentTeal : _cDisabledBg,
          foregroundColor: enabled ? Colors.white : _cDisabledLabel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1_outlined, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Save Member',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}
