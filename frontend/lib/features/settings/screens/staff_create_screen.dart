import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/staff_models.dart';
import '../providers/staff_providers.dart';

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
  String? _emailError;
  String? _passwordError;

  // Set only after a successful create — switches this screen into the
  // "show the password once" view.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add staff')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: _emailError,
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Temporary password',
                errorText: _passwordError,
                helperText:
                    'At least 8 characters. They\'ll change it on '
                    'first login.',
              ),
              obscureText: true,
              // Only length is checked here on purpose — the server owns
              // the real rules (common-password, similarity-to-name,
              // numeric-only checks). Trying to copy those client-side
              // would just drift out of sync with Django over time.
              validator: (v) =>
                  (v == null || v.length < 8) ? 'At least 8 characters' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'owner', child: Text('Owner')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'staff'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create staff account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    final email = _createdStaff!.email;
    final password = _createdPassword!;

    return Scaffold(
      appBar: AppBar(title: const Text('Staff created')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_createdStaff!.fullName} was added. Share these '
              'credentials with them now — this password is shown only '
              'this once and the app will not store it anywhere.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('Email: $email'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: SelectableText('Password: $password')),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy password',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: password));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password copied')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "They'll be asked to set a new password the first time "
              'they log in.',
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _emailError = null;
      _passwordError = null;
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
      setState(() {
        _createdStaff = staff;
        _createdPassword = password;
        _submitting = false;
      });
    } on ApiException catch (e) {
      // ⚠️ ASSUMPTION: I'm guessing ApiException exposes a
      // `Map<String, dynamic>? fieldErrors` (matching the plan's mention
      // of "surface its fieldErrors on the form"). If your ApiException
      // doesn't have that field, this line won't compile — send me
      // api_exception.dart and I'll match it exactly.
      final errors = e.fieldErrors;
      setState(() {
        _submitting = false;
        _emailError = (errors?['email'] as List?)?.join(' ');
        _passwordError = (errors?['password'] as List?)?.join(' ');
      });
      if (mounted && errors == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
      }
    }
  }
}
