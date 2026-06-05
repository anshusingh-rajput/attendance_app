import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? prefillUsername;
  final bool isChangePassword;
  const ForgotPasswordScreen({
    super.key,
    this.prefillUsername,
    this.isChangePassword = false,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _usernameCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _busy = false;
  bool _emailSent = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.prefillUsername != null && widget.prefillUsername!.isNotEmpty) {
      _usernameCtrl.text = widget.prefillUsername!;
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _tokenCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRequestReset() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      _snack('Please enter your username');
      return;
    }
    setState(() => _busy = true);
    final result = await _auth.requestForgotPassword(username);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.isSuccess) {
      setState(() => _emailSent = true);
      _snack('Password reset email sent. Check your inbox.');
    } else {
      _snack(result.error ?? 'Request failed');
    }
  }

  Future<void> _onResetPassword() async {
    final token = _tokenCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;
    if (token.isEmpty) {
      _snack('Enter the token from your email');
      return;
    }
    if (newPassword.length < 6) {
      _snack('New password must be at least 6 characters');
      return;
    }
    setState(() => _busy = true);
    final result = await _auth.resetPassword(
      token: token,
      newPassword: newPassword,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.isSuccess) {
      _snack(widget.isChangePassword
          ? 'Password changed. Please login again with the new password.'
          : 'Password reset successfully. Please login.');
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      if (widget.isChangePassword) {
        await _auth.logout();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pop();
      }
    } else {
      _snack(result.error ?? 'Reset failed');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        title: Text(
          widget.isChangePassword ? 'Change Password' : 'Forgot Password',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const AppLogo(size: 64, iconSize: 32, radius: 14),
              const SizedBox(height: 24),
              Text(
                _emailSent
                    ? 'Enter reset token'
                    : (widget.isChangePassword
                        ? 'Change your password'
                        : 'Reset your password'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _emailSent
                    ? 'Check your email for the reset token. Paste it below '
                        'and enter your new password.'
                    : (widget.isChangePassword
                        ? 'We will send a reset token to your registered '
                            'email. Use it below to set a new password.'
                        : 'Enter your username. We will send a password '
                            'reset token to your registered email.'),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const SizedBox(height: 28),
              if (!_emailSent) ..._buildRequestForm() else ..._buildResetForm(),
              const SizedBox(height: 16),
              if (_emailSent)
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _emailSent = false;
                              _tokenCtrl.clear();
                              _newPasswordCtrl.clear();
                            }),
                    child: const Text('Resend / use different username'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRequestForm() {
    return [
      const Text(
        'Username',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.darkText,
        ),
      ),
      const SizedBox(height: 8),
      _Field(
        controller: _usernameCtrl,
        hint: 'Enter your username',
        icon: Icons.person_outline,
      ),
      const SizedBox(height: 24),
      _PrimaryButton(
        label: 'Send Reset Email',
        busy: _busy,
        onTap: _onRequestReset,
      ),
    ];
  }

  List<Widget> _buildResetForm() {
    return [
      const Text(
        'Reset Token',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.darkText,
        ),
      ),
      const SizedBox(height: 8),
      _Field(
        controller: _tokenCtrl,
        hint: 'Paste token from email',
        icon: Icons.vpn_key_outlined,
      ),
      const SizedBox(height: 18),
      const Text(
        'New Password',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.darkText,
        ),
      ),
      const SizedBox(height: 8),
      _Field(
        controller: _newPasswordCtrl,
        hint: 'Enter new password (min 6 chars)',
        icon: Icons.lock_outline_rounded,
        obscure: _obscure,
        suffix: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      const SizedBox(height: 24),
      _PrimaryButton(
        label: 'Reset Password',
        busy: _busy,
        onTap: _onResetPassword,
      ),
    ];
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.subtitleGrey),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
