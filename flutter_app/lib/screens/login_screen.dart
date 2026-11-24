import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'team_setup_screen.dart';
import 'otp_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  /// OTP verify ke baad aane par email pehle se bhara hua aata hai
  final String? prefillEmail;

  /// OTP verify ke baad "Email verified, ab login karo" message
  final String? infoMessage;

  const LoginScreen({super.key, this.prefillEmail, this.infoMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) _emailCtrl.text = widget.prefillEmail!;
    if (widget.infoMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.infoMessage!),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailCtrl.text.trim().toLowerCase();
    final result = await AuthService.login(
      email: email,
      password: _passCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TeamSetupScreen()),
        (route) => false,
      );
    } else if (result['requiresVerification'] == true) {
      // Email verify nahi hua tha -> OTP screen par bhejo
      _showError(result['message'] ?? 'Please verify your email');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            email: result['email'] ?? email,
            emailSent: result['emailSent'] != false,
            emailError: result['emailError'],
            devOtp: result['devOtp'],
          ),
        ),
      );
    } else {
      _showError(result['message'] ?? 'Login failed');
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 60),

                // ---- Logo ----
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryPink.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.air, color: Colors.white, size: 36),
                  ),
                ),

                const SizedBox(height: 28),

                // ---- Title ----
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                    children: [
                      TextSpan(text: 'Welcome '),
                      TextSpan(
                        text: 'Back',
                        style: TextStyle(color: AppColors.primaryPink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sign in to Kite Battle Arena',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 15),
                ),

                const SizedBox(height: 40),

                // ---- Email Field ----
                _buildLabel('Email'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined, color: AppColors.textGrey),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email required';
                    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v)) {
                      return 'Enter valid email';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                // ---- Password Field ----
                _buildLabel('Password'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textGrey),
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() => _obscurePass = !_obscurePass),
                      child: Icon(
                        _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password required';
                    if (v.length < 6) return 'Min 6 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // ---- Login Button ----
                GradientButton(
                  text: 'Sign In',
                  icon: Icons.login_rounded,
                  isLoading: _isLoading,
                  onPressed: _login,
                ),

                const SizedBox(height: 24),

                // ---- Forgot password (left) + Register (right) ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(
                            prefillEmail: _emailCtrl.text.trim(),
                          ),
                        ),
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: AppColors.primaryPurple,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'New here? ',
                          style: TextStyle(color: AppColors.textGrey, fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          ),
                          child: const Text(
                            'Register',
                            style: TextStyle(
                              color: AppColors.primaryPink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
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
}
