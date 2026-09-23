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

  // UI-only state, not wired into claim logic.
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  static const _brandGreen = Color(0xFF0E5B44);
  static const _linkTeal = Color(0xFF1F9D7C);
  static const _labelGrey = Color(0xFF8A9591);

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // D2 — opens the shared scanner (the exact same camera engine the
  // staff check-in scanner uses) configured to read a claim QR
  // (FDCLAIM1|<code>) instead of verifying a check-in one. Purely
  // local parsing on the other side, no server round trip — the email
  // field stays required regardless, since the code alone is exactly
  // what a photographed claim card would hand anyone who found it.
  Future<void> _scanCode() async {
    final code = await context.push<String>('/claim/scan');
    if (code == null || !mounted) return;
    setState(() {
      _codeController.text = code.replaceAll(' ', '').toUpperCase();
    });
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

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    String? helper,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, size: 19, color: Colors.grey.shade500),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF7F9F8),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE3E8E6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE3E8E6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _brandGreen, width: 1.4),
      ),
      helperText: errorText == null ? helper : null,
      helperStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
      errorText: errorText,
      errorStyle: const TextStyle(fontSize: 11.5),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _labelGrey,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(
          color: Colors.black87,
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set up your account',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your gym gave you a one-time code. Use it here to '
                      'set up your own login.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    _fieldLabel('EMAIL ADDRESS'),
                    TextField(
                      controller: _emailController,
                      enabled: !_isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: _fieldDecoration(
                        hint: 'e.g. member@email.com',
                        icon: Icons.mail_outline,
                        helper: 'The address your gym has on file',
                      ),
                    ),
                    const SizedBox(height: 18),

                    _fieldLabel('CLAIM CODE'),
                    TextField(
                      controller: _codeController,
                      enabled: !_isSubmitting,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        _ClaimCodeFormatter(),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: _fieldDecoration(
                        hint: 'e.g. 8-character gym code',
                        icon: Icons.confirmation_number_outlined,
                        helper: '8 characters, given to you by your gym',
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 20,
                            color: Colors.grey.shade500,
                          ),
                          tooltip: 'Scan',
                          onPressed: _isSubmitting ? null : _scanCode,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    _fieldLabel('CHOOSE A PASSWORD'),
                    TextField(
                      controller: _passwordController,
                      enabled: !_isSubmitting,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: _fieldDecoration(
                        hint: '••••••••••',
                        icon: Icons.lock_outline,
                        helper: 'The code is one-time — this password is yours',
                        errorText: _passwordError,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 19,
                            color: Colors.grey.shade500,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    _fieldLabel('CONFIRM PASSWORD'),
                    TextField(
                      controller: _confirmController,
                      enabled: !_isSubmitting,
                      obscureText: _obscureConfirm,
                      onSubmitted: (_) => _submit(),
                      decoration: _fieldDecoration(
                        hint: '••••••••••',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 19,
                            color: Colors.grey.shade500,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    if (_generalError != null) ...[
                      Text(
                        _generalError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                      if (_accountAlreadyExists) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _brandGreen),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: () => context.go('/login/member'),
                            child: const Text(
                              'Sign in instead',
                              style: TextStyle(
                                color: _brandGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Set up account',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                          children: [
                            const TextSpan(text: 'Already activated? '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: GestureDetector(
                                onTap: _isSubmitting
                                    ? null
                                    : () => context.go('/login/member'),
                                child: const Text(
                                  'Log in',
                                  style: TextStyle(
                                    color: _linkTeal,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    Center(
                      child: GestureDetector(
                        onTap: () => context.push('/help'),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            style: TextStyle(fontSize: 11.5, color: Colors.grey),
                            children: [
                              TextSpan(text: 'Need assistance? '),
                              TextSpan(
                                text: 'Contact gym staff',
                                style: TextStyle(
                                  color: _linkTeal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
