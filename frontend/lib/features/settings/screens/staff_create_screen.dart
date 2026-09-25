import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../data/staff_models.dart';
import '../providers/staff_providers.dart';

/// Turns the server's email error into plain language. Emails are unique
/// across ALL gyms on the platform, so "already exists" can mean someone
/// at this gym or at another one.
String staffEmailErrorMessage(String serverText) {
  final t = serverText.toLowerCase();
  if (t.contains('already exists') || t.contains('already')) {
    return 'This email already has an account — either here or at another '
        'gym. Use a different email address.';
  }
  if (t.contains('valid')) return 'Enter a valid email address.';
  return serverText;
}

/// Turns Django's password-validator wording into something an owner can
/// act on. Unknown messages pass through unchanged.
String staffPasswordErrorMessage(String serverText) {
  final t = serverText.toLowerCase();
  if (t.contains('too common')) {
    return 'That password is too common. Pick something harder to guess.';
  }
  if (t.contains('entirely numeric')) {
    return "The password can't be only numbers. Add some letters.";
  }
  if (t.contains('too similar')) {
    return "The password is too close to the person's name or email.";
  }
  if (t.contains('too short') || t.contains('at least 8')) {
    return 'The password needs at least 8 characters.';
  }
  return serverText;
}

class StaffCreateScreen extends ConsumerStatefulWidget {
  const StaffCreateScreen({super.key});

  @override
  ConsumerState<StaffCreateScreen> createState() => _StaffCreateScreenState();
}

class _StaffCreateScreenState extends ConsumerState<StaffCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'staff';
  bool _submitting = false;
  // Visible by default: the owner reads this out loud, so hiding it just
  // makes the job harder.
  bool _hidePassword = false;
  String? _emailError;
  String? _passwordError;
  String? _formError;

  // Set only after a successful create — switches this screen into the
  // recap view. Kept in memory only, never stored.
  StaffMember? _createdStaff;
  String? _createdPassword;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _createdStaff != null ? _buildSuccessView() : _buildFormView();
  }

  Widget _buildFormView() {
    final isOwnerRole = _role == 'owner';

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('Add staff'),
        backgroundColor: AppColors.pageBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              TextFormField(
                controller: _fullNameController,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter their name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: _emailError,
                  errorMaxLines: 3,
                ),
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
                validator: (v) {
                  final t = v?.trim() ?? '';
                  return (t.isEmpty || !t.contains('@') || !t.contains('.'))
                      ? 'Enter a valid email address'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordController,
                enabled: !_submitting,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  errorText: _passwordError,
                  errorMaxLines: 3,
                  helperText:
                      'At least 8 characters. They set their own password '
                      'the first time they sign in.',
                  helperMaxLines: 3,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _hidePassword ? 'Show password' : 'Hide password',
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                  ),
                ),
                onChanged: (_) {
                  if (_passwordError != null) {
                    setState(() => _passwordError = null);
                  }
                },
                // Only length is checked here on purpose — the server owns
                // the real rules (common-password, similarity, numeric-only),
                // and its answers are translated in _submit.
                validator: (v) => (v == null || v.length < 8)
                    ? 'At least 8 characters'
                    : null,
              ),
              const SizedBox(height: 20),
              const Text(
                'Role',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.subtle,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'staff', label: Text('Staff')),
                    ButtonSegment(value: 'owner', label: Text('Owner')),
                  ],
                  selected: {_role},
                  onSelectionChanged: _submitting
                      ? null
                      : (s) => setState(() => _role = s.first),
                ),
              ),
              const SizedBox(height: 12),
              if (isOwnerRole)
                const _OwnerWarning()
              else
                const _StaffAccessNote(),
              if (_formError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formError!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.errorText,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final staff = _createdStaff!;
    final email = staff.email;
    final password = _createdPassword!;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('Account created'),
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.pageBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.accentTeal,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${staff.fullName} was added.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Pass these on now. The password is shown only this once, and '
              'the app does not store it.',
              style: TextStyle(fontSize: 13, color: AppColors.subtle),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CredentialLine(label: 'Email', value: email),
                  const SizedBox(height: 12),
                  _CredentialLine(label: 'Password', value: password),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _copy(
                        'Email: $email\nPassword: $password',
                        'Email and password copied',
                      ),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy email & password'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentTeal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "They'll be asked to choose a new password the first time they "
              'sign in.',
              style: TextStyle(fontSize: 13, color: AppColors.subtle),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _emailError = null;
      _passwordError = null;
      _formError = null;
    });

    try {
      final password = _passwordController.text;
      final staff = await ref
          .read(staffRepositoryProvider)
          .createStaff(
            fullName: _fullNameController.text.trim(),
            email: _emailController.text,
            password: password,
            role: _role,
          );
      ref.invalidate(staffListProvider);
      if (!mounted) return;
      setState(() {
        _createdStaff = staff;
        _createdPassword = password;
        _submitting = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = e.fieldErrors;
      final emailErrors = errors?['email'];
      final passwordErrors = errors?['password'];
      setState(() {
        _submitting = false;
        _emailError = (emailErrors != null && emailErrors.isNotEmpty)
            ? staffEmailErrorMessage(emailErrors.join(' '))
            : null;
        _passwordError = (passwordErrors != null && passwordErrors.isNotEmpty)
            ? staffPasswordErrorMessage(passwordErrors.join(' '))
            : null;
        if (_emailError == null && _passwordError == null) {
          _formError = switch (e.kind) {
            ApiExceptionKind.forbidden =>
              'Only the gym owner can add staff accounts.',
            ApiExceptionKind.network =>
              'No connection. Adding staff needs the internet — try again '
                  'when you are back online.',
            _ => e.message,
          };
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = "Couldn't create the account. Please try again.";
      });
    }
  }
}

class _CredentialLine extends StatelessWidget {
  const _CredentialLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// Shown for the Staff role. Mirrors the real backend permissions.
class _StaffAccessNote extends StatelessWidget {
  const _StaffAccessNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What a staff account can do',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: 8),
          _AccessLine(
            ok: true,
            text:
                'Add and edit members, check them in, and reset a member’s '
                'app password',
          ),
          _AccessLine(
            ok: true,
            text: 'Ring up sales, view products, and adjust stock',
          ),
          _AccessLine(
            ok: true,
            text: 'Post announcements and events, and verify event results',
          ),
          _AccessLine(
            ok: false,
            text:
                'Can’t see sales analytics, the activity log or sales '
                'history',
          ),
          _AccessLine(
            ok: false,
            text: 'Can’t change plans, products, class times or gym settings',
          ),
          _AccessLine(
            ok: false,
            text:
                'Can’t manage staff, archive members, reset a member’s QR '
                'card or void sales',
          ),
        ],
      ),
    );
  }
}

class _AccessLine extends StatelessWidget {
  const _AccessLine({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 16,
            color: ok ? AppColors.accentTeal : AppColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: AppColors.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when Owner is picked: a second owner is not a limited account.
class _OwnerWarning extends StatelessWidget {
  const _OwnerWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.expiringIcon,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: AppColors.expiringBg,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'A second owner can do everything you can — including '
              'managing staff and seeing all the money (sales analytics, '
              'activity log and sales history). Only choose Owner for '
              'someone you trust fully.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.expiringBg,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
