import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailCtrl.text.trim().toLowerCase();
    final result = await AuthService.register(
      email: email,
      password: _passCtrl.text,
      name: _nameCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      // Navigate to the OTP screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            email: email,
            emailSent: result['emailSent'] != false,
            emailError: result['emailError'],
            devOtp: result['devOtp'],
          ),
        ),
      );
    } else {
      _showError(result['message'] ?? 'Registration failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPink,
      body: SafeArea(
        child: Column(
          children: [
            // ---- Back Button ----
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 16,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ),

            // ---- Scrollable Form ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Logo - same as screenshots
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primaryPink,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Icon(Icons.air, color: AppColors.primaryPink, size: 30),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Title - "Create Account" with pink highlight
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                          children: [
                            TextSpan(text: 'Create '),
                            TextSpan(
                              text: 'Account',
                              style: TextStyle(color: AppColors.primaryPink),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Join the Kite Battle Arena',
                        style: TextStyle(color: AppColors.textGrey, fontSize: 14),
                      ),

                      const SizedBox(height: 28),

                      // Email
                      _buildField(
                        label: 'Email',
                        controller: _emailCtrl,
                        hint: 'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Email required';
                          if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v)) {
                            return 'Enter valid email';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 14),

                      // Password
                      _buildField(
                        label: 'Password',
                        controller: _passCtrl,
                        hint: '••••••••',
                        obscure: _obscurePass,
                        onToggleObscure: () =>
                            setState(() => _obscurePass = !_obscurePass),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password required';
                          if (v.length < 6) return 'Min 6 characters';
                          return null;
                        },
                      ),

                      const SizedBox(height: 14),

                      // Confirm Password
                      _buildField(
                        label: 'Confirm password',
                        controller: _confirmPassCtrl,
                        hint: '••••••••',
                        obscure: _obscureConfirm,
                        onToggleObscure: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Confirm your password';
                          if (v != _passCtrl.text) return 'Passwords do not match';
                          return null;
                        },
                      ),

                      const SizedBox(height: 14),

                      // Name
                      _buildField(
                        label: 'Name',
                        controller: _nameCtrl,
                        hint: 'Your name',
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Name required' : null,
                      ),

                      const SizedBox(height: 14),

                      // City
                      _buildField(
                        label: 'City',
                        controller: _cityCtrl,
                        hint: 'Jaipur',
                        validator: (v) =>
                            v == null || v.isEmpty ? 'City required' : null,
                      ),

                      const SizedBox(height: 28),

                      // Create Account Button
                      GradientButton(
                        text: 'Create account',
                        icon: Icons.person_add_outlined,
                        isLoading: _isLoading,
                        onPressed: _register,
                      ),

                      const SizedBox(height: 20),

                      // Sign in link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text(
                            'Already registered? ',
                            style: TextStyle(color: AppColors.textGrey, fontSize: 14),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              'Login',
                              style: TextStyle(
                                color: AppColors.primaryPink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: onToggleObscure != null
                ? GestureDetector(
                    onTap: onToggleObscure,
                    child: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textGrey,
                      size: 20,
                    ),
                  )
                : null,
          ),
          validator: validator,
        ),
      ],
    );
  }
}
