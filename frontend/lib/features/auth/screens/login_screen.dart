import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_exception.dart';
import '../providers/auth_providers.dart';

enum AuthRole { owner, member }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.role});

  final AuthRole role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text; // never trim the password

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).login(email, password);
      // Success flips AuthState to authenticated; the router reacts to
      // that and sends the person to the right shell for their
      // account_type. No navigation call belongs here.
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.role == AuthRole.owner;

    return Scaffold(
      appBar: AppBar(),
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
                    isOwner ? 'Owner sign in' : 'Member sign in',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !_isSubmitting,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Log in'),
                  ),
                  const SizedBox(height: 24),
                  // Deliberately different secondary action per role, and
                  // visually distinct from each other — this is the
                  // guard against a member accidentally hitting "create
                  // a gym" and an owner accidentally hitting "claim a
                  // code". See RolePickerScreen's doc comment.
                  if (isOwner)
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => context.push('/signup'),
                      child: const Text(
                        "Don't have a gym account yet? "
                        'Create one',
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => context.push('/claim'),
                      child: const Text(
                        'Have a code from your gym? '
                        'Set up your account',
                      ),
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
