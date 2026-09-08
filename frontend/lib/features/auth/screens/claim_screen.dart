import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_exception.dart';
import '../providers/auth_providers.dart';

/// Forces every character to uppercase and strips whitespace as the
/// person types. The claim-code alphabet excludes O/0 and I/1 on
/// purpose — these get read aloud at a front desk — but people will
/// still type lowercase, so this formatter does the normalizing for
/// them rather than rejecting input.
class _ClaimCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(' ', '').toUpperCase();
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

/// Redeems a staff-issued one-time code into a real member login. This
/// screen deliberately cannot work offline and never queues — it creates
/// a server-side account, and there's nothing sensible to do with a
/// queued claim. See AuthApi.claim()'s doc comment for the same point.
class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key});

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;
  String? _generalError;
  bool _accountAlreadyExists = false;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    setState(() {
      _generalError = null;
      _accountAlreadyExists = false;
      _passwordError = null;
    });

    // Client-side check first — no reason to hit the server for a typo
    // in the confirm field.
    if (_passwordController.text != _confirmController.text) {
      setState(() => _passwordError = 'Passwords do not match.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref
          .read(authControllerProvider.notifier)
          .claim(
            email: _emailController.text.trim(),
            claimCode: _codeController.text.trim(),
            password: _passwordController.text,
          );
      // Success flips AuthState to authenticated; the router sees
      // account_type == 'member' and sends them to the member shell.
      // No navigation call belongs here.
    } on ApiException catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _handleError(ApiException e) {
    switch (e.kind) {
      case ApiExceptionKind.throttled:
        setState(() {
          _generalError = 'Too many attempts. Please try again later.';
        });
        break;

      case ApiExceptionKind.network:
        setState(() {
          _generalError =
              'You need an internet connection to set up your account.';
        });
        break;

      case ApiExceptionKind.validation:
        final passwordErrors = e.fieldErrors?['password'];
        if (passwordErrors != null && passwordErrors.isNotEmpty) {
          setState(() => _passwordError = passwordErrors.first);
          break;
        }

        // Everything else (wrong email/code/expired/already-used, or
        // "an account already exists for this email") arrives as a
        // plain non_field_errors message — same shape for both, so the
        // only way to tell them apart is the message text itself.
        final alreadyExists = e.message.toLowerCase().contains(
          'already exists',
        );
        setState(() {
          _generalError = e.message; // server's message, verbatim
          _accountAlreadyExists = alreadyExists;
        });
        break;

      default:
        setState(() {
          _generalError = e.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your account')),
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
                    'Your gym gave you a one-time code. Use it here to '
                    'set up your own login.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      helperText: 'The address your gym has on file',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      _ClaimCodeFormatter(),
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Claim code',
                      helperText: '8 characters, given to you by your gym',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !_isSubmitting,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Choose a password',
                      helperText:
                          'The code is one-time — this password is yours',
                      errorText: _passwordError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmController,
                    enabled: !_isSubmitting,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  if (_generalError != null) ...[
                    Text(
                      _generalError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_accountAlreadyExists) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => context.go('/login/member'),
                        child: const Text('Sign in instead'),
                      ),
                    ],
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
                        : const Text('Set up account'),
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
