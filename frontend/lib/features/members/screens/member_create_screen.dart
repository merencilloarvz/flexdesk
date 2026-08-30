import 'package:flexdesk/features/members/data/members_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/providers/auth_providers.dart';
import '../providers/members_providers.dart';
import '../providers/plans_provider.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cFieldBg = Color(0xFFF5F6F7);
const Color _cCardBg = Colors.white;
const Color _cAccentTeal = Color(0xFF0F6E56);
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

  // The backend still splits a member into first_name/last_name, but one
  // combined "Name" field is simpler for the person typing. Everything
  // after the first space becomes the last name — good enough for
  // "Juan Dela Cruz" (first: Juan, last: Dela Cruz); a single-word name
  // just leaves last_name blank, which the backend already allows.
  (String, String) _splitName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return (first, last);
  }

  Future<void> _submit({
    required String gymId,
    required String homeLocationId,
  }) async {
    if (_isSubmitting) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() {
        _fieldErrors = {
          'first_name': ['Name is required.'],
        };
      });
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
        context.pop();
      case CreateMemberOutcome.queuedOffline:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved — will sync when back online.')),
        );
        context.pop();
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

    final gymId = authState.user.gym.id;
    final homeLocationId = authState.user.defaultLocationId;
    final plansAsync = ref.watch(activePlansProvider(gymId));

    return Scaffold(
      backgroundColor: _cPageBg,
      appBar: AppBar(
        backgroundColor: _cPageBg,
        elevation: 0,
        title: const Text(
          'Add Member',
          style: TextStyle(color: _cInk, fontWeight: FontWeight.w500),
        ),
        iconTheme: const IconThemeData(color: _cInk),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cCardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _textField(
                      label: 'Name',
                      hint: 'Juan Dela Cruz',
                      controller: _nameCtrl,
                      error: _errorFor('first_name') ?? _errorFor('last_name'),
                    ),
                    const SizedBox(height: 16),
                    _textField(
                      label: 'Phone (optional)',
                      hint: '0912 345 6789',
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      error: _errorFor('phone'),
                    ),
                    const SizedBox(height: 16),
                    _textField(
                      label: 'Email (optional)',
                      hint: 'juan@example.com',
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      error: _errorFor('email'),
                    ),
                    const SizedBox(height: 16),
                    _planField(plansAsync),
                  ],
                ),
              ),

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

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: _cSubtle,
    ),
  );

  Widget _textField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(label),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _cFieldBg,
            borderRadius: BorderRadius.circular(12),
            border: error != null ? Border.all(color: _cErrorText) : null,
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: !_isSubmitting,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _cMuted, fontSize: 15),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(fontSize: 12, color: _cErrorText)),
        ],
      ],
    );
  }

  Widget _planField(AsyncValue plansAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _label('Plan'),
            GestureDetector(
              onTap: () => context.push('/plans/manage'),
              child: const Text(
                'Manage plans',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _cAccentTeal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
    );
  }

  Widget _saveButton({
    required bool enabled,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: (enabled && !_isSubmitting) ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? _cInk : _cDisabledBg,
          foregroundColor: enabled ? Colors.white : _cDisabledLabel,
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
            : const Text(
                'Save member',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
