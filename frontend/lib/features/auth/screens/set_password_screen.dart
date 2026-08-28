// lib/features/auth/screens/set_password_screen.dart
import 'package:flutter/material.dart';

const Color _cPageBg = Color(0xFFEDEFF0);
const Color _cInk = Color(0xFF0E1A13);
const Color _cSubtle = Color(0xFF6B7570);
const Color _cMuted = Color(0xFF8A938E);
const Color _cFieldBg = Color(0xFFF5F6F7);
const Color _cCardBg = Colors.white;
const Color _cAccentGreen = Color(0xFF39C77F);
const Color _cErrorBg = Color(0xFFFCEBE8);
const Color _cErrorText = Color(0xFF9E3125);
const Color _cSuccessBg = Color(0xFFE6F6ED);
const Color _cLinkGreen = Color(0xFF1F7A4D);
const Color _cDisabledBg = Color(0xFFE2E5E3);
const Color _cDisabledLabel = Color(0xFF9AA39E);

class TempPasswordResult {
  const TempPasswordResult.success() : errorMessage = null;
  const TempPasswordResult.failure(this.errorMessage);
  final String? errorMessage;
  bool get isSuccess => errorMessage == null;
}

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({
    super.key,
    required this.staffEmail,
    this.onVerifyTempPassword,
    this.onPasswordSet,
  });

  final String staffEmail;
  final Future<TempPasswordResult> Function(
    String tempPassword,
    String newPassword,
  )?
  onVerifyTempPassword;
  final VoidCallback? onPasswordSet;

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final _curCtrl = TextEditingController();
  final _nwCtrl = TextEditingController();
  final _cfCtrl = TextEditingController();

  bool _showCur = false;
  bool _showNw = false;
  bool _showCf = false;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _curCtrl.dispose();
    _nwCtrl.dispose();
    _cfCtrl.dispose();
    super.dispose();
  }

  bool get _isValid {
    final cur = _curCtrl.text;
    final nw = _nwCtrl.text;
    final cf = _cfCtrl.text;
    return cur.isNotEmpty && nw.length >= 8 && cf == nw;
  }

  Future<void> _submit() async {
    if (_loading || !_isValid) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    final verify = widget.onVerifyTempPassword;
    if (verify == null) {
      setState(() => _loading = false);
      return;
    }

    final result = await verify(_curCtrl.text, _nwCtrl.text);
    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _loading = false;
        _done = true;
      });
      widget.onPasswordSet?.call();
    } else {
      setState(() {
        _loading = false;
        _error = result.errorMessage ?? "That temporary password isn't right.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cPageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _done ? _buildSuccess() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final mismatch = _cfCtrl.text.isNotEmpty && _cfCtrl.text != _nwCtrl.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _badge(),
        const SizedBox(height: 20),
        const Text(
          'Set your new password',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: _cInk,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your gym owner created a temporary password for you. Choose a new one to continue.',
          style: TextStyle(fontSize: 15, color: _cSubtle),
        ),
        const SizedBox(height: 24),

        if (_error != null) _errorBanner(_error!),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cCardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                label: 'Temporary password',
                controller: _curCtrl,
                obscure: !_showCur,
                onToggle: () => setState(() => _showCur = !_showCur),
                onChanged: () => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              _field(
                label: 'New password',
                controller: _nwCtrl,
                obscure: !_showNw,
                onToggle: () => setState(() => _showNw = !_showNw),
                onChanged: () => setState(() {}),
                helper: 'Minimum 8 characters.',
              ),
              const SizedBox(height: 20),
              _field(
                label: 'Confirm new password',
                controller: _cfCtrl,
                obscure: !_showCf,
                onToggle: () => setState(() => _showCf = !_showCf),
                onChanged: () => setState(() {}),
                helper: mismatch ? "Passwords don't match yet." : null,
                helperColor: mismatch ? Colors.red : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _continueButton(),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Signed in as ${widget.staffEmail}',
            style: const TextStyle(fontSize: 13, color: _cMuted),
          ),
        ),
      ],
    );
  }

  Widget _badge() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _cInk,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _cAccentGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'FLEXDESK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cErrorBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _cErrorText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _cErrorText, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required VoidCallback onChanged,
    String? helper,
    Color? helperColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _cSubtle,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _cFieldBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
              TextButton(
                onPressed: onToggle,
                child: Text(obscure ? 'Show' : 'Hide'),
              ),
            ],
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper,
            style: TextStyle(fontSize: 12, color: helperColor ?? _cMuted),
          ),
        ],
      ],
    );
  }

  Widget _continueButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: (_isValid && !_loading) ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isValid ? _cInk : _cDisabledBg,
          foregroundColor: _isValid ? Colors.white : _cDisabledLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: _cSuccessBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 32, color: _cLinkGreen),
        ),
        const SizedBox(height: 20),
        const Text(
          'Password updated',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _cInk,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "You're all set. Taking you to the front desk…",
          textAlign: TextAlign.center,
          style: TextStyle(color: _cSubtle),
        ),
      ],
    );
  }
}
