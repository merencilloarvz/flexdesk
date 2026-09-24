import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/theme/colors.dart';
import '../providers/auth_providers.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_version.dart';
import '../widgets/fade_slide_in.dart';

const _supportEmail = 'flexdeskisufst@gmail.com';

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

  // UI-only state, not wired into auth logic.
  bool _obscurePassword = true;
  bool _rememberDevice = true;

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
      setState(() => _errorMessage = _friendlyLoginError(e));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // Informational only — there's no self-service reset flow. Members are
  // resolved in person at the front desk (MemberViewSet.reset_password);
  // owners email support directly since there's no email provider
  // configured to verify an owner's identity remotely.
  void _showForgotPasswordMessage() {
    if (widget.role == AuthRole.member) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('See gym staff to reset your password.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Email $_supportEmail to reset your password.'),
        action: SnackBarAction(label: 'Email', onPressed: _emailSupport),
      ),
    );
  }

  Future<void> _emailSupport() async {
    try {
      await launchUrl(Uri(scheme: 'mailto', path: _supportEmail));
    } catch (_) {
      // Best-effort — no mail client configured. The address is still
      // visible in the snackbar text.
    }
  }

  // Google sign-in isn't built yet — the button is here so the layout
  // and flow are ready for it, but it doesn't perform any auth.
  void _showGoogleComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signing in with Google is coming soon.')),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
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
        borderSide: const BorderSide(color: AppColors.accentTeal, width: 1.4),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.role == AuthRole.owner;

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
                child: FadeSlideIn(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      const Center(child: AppLogo()),
                      const SizedBox(height: 24),
                      Text(
                        isOwner ? 'Owner sign in' : 'Member sign in',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isOwner
                            ? 'Sign in to check members in, ring up sales, '
                                  'and manage your gym.'
                            : 'Sign in to show your pass, check your visits, '
                                  'and catch what\'s happening at your gym.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),

                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : _showGoogleComingSoon,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF4285F4),
                                ),
                                child: const Text(
                                  'G',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Continue with Google',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _fieldLabel('Email'),
                      TextField(
                        controller: _emailController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: _fieldDecoration(
                          hint: 'you@example.com',
                          icon: Icons.mail_outline,
                        ),
                      ),
                      const SizedBox(height: 18),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _fieldLabel('Password'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GestureDetector(
                              onTap: _showForgotPasswordMessage,
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  color: AppColors.accentTeal,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _passwordController,
                        enabled: !_isSubmitting,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                        decoration: _fieldDecoration(
                          hint: 'Password',
                          icon: Icons.lock_outline,
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
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          SizedBox(
                            height: 22,
                            width: 22,
                            child: Checkbox(
                              value: _rememberDevice,
                              activeColor: AppColors.accentTeal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: _isSubmitting
                                  ? null
                                  : (v) => setState(
                                      () => _rememberDevice = v ?? true,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Keep me signed in on this device',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

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

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentTeal,
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
                                      'Log in',
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

                      // Deliberately different secondary action per role, and
                      // visually distinct from each other — this is the
                      // guard against a member accidentally hitting "create
                      // a gym" and an owner accidentally hitting "claim a
                      // code". See RolePickerScreen's doc comment.
                      Center(
                        child: isOwner
                            ? RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                  children: [
                                    const TextSpan(
                                      text: "Don't have a gym account yet? ",
                                    ),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: GestureDetector(
                                        onTap: _isSubmitting
                                            ? null
                                            : () => context.push('/signup'),
                                        child: const Text(
                                          'Create one',
                                          style: TextStyle(
                                            color: AppColors.accentTeal,
                                            fontWeight: FontWeight.w600,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : GestureDetector(
                                onTap: _isSubmitting
                                    ? null
                                    : () => context.push('/claim'),
                                child: RichText(
                                  textAlign: TextAlign.center,
                                  text: const TextSpan(
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                    children: [
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: Icon(
                                          Icons.qr_code_2,
                                          size: 15,
                                          color: AppColors.accentTeal,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '  Have a code from your gym? ',
                                      ),
                                      TextSpan(
                                        text: 'Set up your account',
                                        style: TextStyle(
                                          color: AppColors.accentTeal,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 28),

                      Center(
                        child: TextButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => context.push('/help'),
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Need help?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Center(child: AppVersionText()),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A friendlier read on the raw exception than showing e.message
/// verbatim — a bad login attempt's real server text ("No active
/// account found with the given credentials") is accurate but reads
/// like a system error; these are the same words a person would use.
String _friendlyLoginError(ApiException e) {
  switch (e.kind) {
    case ApiExceptionKind.unauthorized:
    case ApiExceptionKind.validation:
      return "That email or password isn't right. Please try again.";
    case ApiExceptionKind.network:
      return "You'll need an internet connection to sign in.";
    case ApiExceptionKind.throttled:
      return 'Too many attempts. Please wait a moment and try again.';
    case ApiExceptionKind.forbidden:
    case ApiExceptionKind.notFound:
    case ApiExceptionKind.server:
    case ApiExceptionKind.subscriptionRequired:
    case ApiExceptionKind.cancelled:
    case ApiExceptionKind.unknown:
      return 'Something went wrong. Please try again.';
  }
}
