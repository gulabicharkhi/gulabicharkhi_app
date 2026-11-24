import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

/// Forgot Password - Step 3: OTP verify hone ke baad naya password set karo.
/// Success -> Login screen (naye password se login karna hoga).
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String resetToken;
  const ResetPasswordScreen({
    super.key,
    required this.email,
    required this.resetToken,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final result = await AuthService.resetPassword(
      email: widget.email,
      resetToken: widget.resetToken,
      newPassword: _passCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            prefillEmail: widget.email,
            infoMessage: 'Password reset ho gaya! Naye password se login karo.',
          ),
        ),
        (route) => false,
      );
    } else {
      AppUi.snack(context, result['message'] ?? 'Could not reset password',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7B2FBE), AppColors.gradientStart],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryPurple.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.lock_outline_rounded,
                          color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 28),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                      children: [
                        TextSpan(text: 'Reset '),
                        TextSpan(
                          text: 'password',
                          style: TextStyle(color: AppColors.primaryPink),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Set a new password for your account',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  _label('New password'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppColors.textGrey),
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _obscurePass = !_obscurePass),
                        child: Icon(
                          _obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textGrey,
                          size: 20,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password required';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _label('Confirm new password'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppColors.textGrey),
                      suffixIcon: GestureDetector(
                        onTap: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        child: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textGrey,
                          size: 20,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Confirm your password';
                      if (v != _passCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  GradientButton(
                    text: 'Reset password',
                    icon: Icons.check_circle_outline_rounded,
                    isLoading: _isLoading,
                    onPressed: _reset,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      );
}
