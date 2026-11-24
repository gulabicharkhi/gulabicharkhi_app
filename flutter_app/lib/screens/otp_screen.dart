import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'reset_password_screen.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  final bool emailSent; // false => backend email bhej nahi paya
  final String? emailError; // reason (sirf dev mein aata hai)
  final String? devOtp; // sirf NODE_ENV=development mein, jab email fail ho

  /// true => Forgot Password flow (OTP ke baad Reset Password screen)
  final bool isReset;
  const OtpScreen({
    super.key,
    required this.email,
    this.isReset = false,
    this.emailSent = true,
    this.emailError,
    this.devOtp,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  // 6 OTP boxes ke liye 6 controllers
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  late bool _emailSent = widget.emailSent;
  late String? _emailError = widget.emailError;
  late String? _devOtp = widget.devOtp;

  int _resendTimer = 30;
  Timer? _timer;
  bool _isLoading = false;
  bool _isResending = false;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _startTimer(notify: false);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(_shakeController);
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startTimer({bool notify = true}) {
    _timer?.cancel();
    _resendTimer = 30;
    if (notify) setState(() {});
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendTimer <= 0) {
        t.cancel();
      } else {
        setState(() => _resendTimer--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeController.dispose();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  // Paste / autofill ke liye: digits ko index se aage ke boxes mein bhar do
  void _fillFrom(int index, String digits) {
    final clean = digits.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return;
    var i = index;
    for (final ch in clean.split('')) {
      if (i > 5) break;
      _controllers[i].text = ch;
      i++;
    }
    setState(() {});
    if (i > 5) {
      _focusNodes[5].unfocus();
      _verifyOtp();
    } else {
      _focusNodes[i].requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    if (_isLoading) return;
    final otp = _otp;
    if (otp.length < 6) {
      _showError('Enter all 6 digits');
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);
    final result = widget.isReset
        ? await AuthService.verifyResetOtp(email: widget.email, otp: otp)
        : await AuthService.verifyOtp(email: widget.email, otp: otp);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true && widget.isReset) {
      // Forgot password: OTP sahi -> naya password set karne wali screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            email: widget.email,
            resetToken: (result['resetToken'] ?? '').toString(),
          ),
        ),
      );
    } else if (result['success'] == true) {
      // OTP sahi -> pehle Login screen (email pehle se bhara hua)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            prefillEmail: widget.email,
            infoMessage: 'Email verified! Ab login karo.',
          ),
        ),
        (route) => false,
      );
    } else {
      _shakeController.forward(from: 0);
      _showError(result['message'] ?? 'Invalid OTP');
      for (var c in _controllers) {
        c.clear();
      }
      setState(() {});
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendOtp() async {
    if (_resendTimer > 0 || _isResending) return;
    setState(() => _isResending = true);
    final result = widget.isReset
        ? await AuthService.forgotPassword(email: widget.email)
        : await AuthService.resendOtp(email: widget.email);
    if (!mounted) return;
    setState(() => _isResending = false);

    if (result['success'] == true) {
      _startTimer();
      setState(() {
        _emailSent = result['emailSent'] != false;
        _emailError = result['emailError'];
        _devOtp = result['devOtp'];
      });
      if (_emailSent) {
        AppUi.snack(context, 'OTP sent successfully!');
      } else {
        _showError(result['message'] ?? 'OTP email could not be sent');
      }
    } else {
      _showError(result['message'] ?? 'Failed to resend OTP');
    }
  }

  void _showError(String msg) => AppUi.snack(context, msg, error: true);

  // Masked email display: hi@example.com → hi*****@example.com
  String get _maskedEmail {
    final parts = widget.email.split('@');
    if (parts.length != 2) return widget.email;
    final name = parts[0];
    final masked = name.length > 2
        ? '${name.substring(0, 2)}${'*' * (name.length - 2)}'
        : name;
    return '$masked@${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPink,
      body: SafeArea(
        child: Column(
          children: [
            // Back button
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

            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    // Email icon - gradient bg like screenshot
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF7B2FBE),
                            AppColors.gradientStart,
                          ],
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
                        child: Icon(
                          Icons.email_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Title
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                        children: [
                          TextSpan(text: widget.isReset ? 'Verify ' : 'Verify your '),
                          TextSpan(
                            text: widget.isReset ? 'OTP' : 'email',
                            style: const TextStyle(color: AppColors.primaryPink),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Enter the 6-digit code we sent to',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maskedEmail,
                      style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    if (!_emailSent) ...[
                      const SizedBox(height: 20),
                      _buildEmailWarning(),
                    ],

                    SizedBox(height: _emailSent ? 36 : 20),

                    // 6 OTP Boxes with shake animation
                    AnimatedBuilder(
                      animation: _shakeAnim,
                      builder: (_, child) {
                        final v = _shakeAnim.value;
                        final offset = math.sin(v * math.pi * 6) * 10 * (1 - v);
                        return Transform.translate(
                          offset: Offset(offset, 0),
                          child: child,
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (i) => _buildOtpBox(i)),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Resend timer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Didn't receive the code? ",
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 13,
                          ),
                        ),
                        _resendTimer > 0
                            ? Text(
                                'Resend in ${_resendTimer}s',
                                style: const TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : GestureDetector(
                                onTap: _isResending ? null : _resendOtp,
                                child: _isResending
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primaryPink,
                                        ),
                                      )
                                    : const Text(
                                        'Resend now',
                                        style: TextStyle(
                                          color: AppColors.primaryPink,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Wrong email link
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Wrong email? Change it',
                        style: TextStyle(
                          color: AppColors.primaryPurple,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primaryPurple,
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Verify Button
                    GradientButton(
                      text: 'Verify & Continue',
                      isLoading: _isLoading,
                      onPressed: _verifyOtp,
                    ),
                    const SizedBox(height: 24),
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

  // Email na jaane par warning (dev mein OTP tap karke autofill bhi ho jata hai)
  Widget _buildEmailWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "We couldn't email your code",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _emailError ?? 'Tap "Resend now" once the timer ends and try again.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF795548)),
          ),
          if (_devOtp != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _fillFrom(0, _devOtp!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 16, color: AppColors.primaryPink),
                    const SizedBox(width: 6),
                    Text(
                      'DEV: tap to autofill $_devOtp',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryPink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 46,
      height: 56,
      // Backspace par pichle box par jao (stable Focus widget, har build par naya FocusNode nahi)
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _controllers[index].text.isEmpty &&
              index > 0) {
            _controllers[index - 1].clear();
            _focusNodes[index - 1].requestFocus();
            setState(() {});
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextFormField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            fillColor: _controllers[index].text.isNotEmpty
                ? Colors.white
                : const Color(0xFFF3D5E8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryPink, width: 2),
            ),
          ),
          onChanged: (value) {
            if (value.isEmpty) {
              setState(() {});
              return;
            }
            if (value.length >= 3) {
              // Paste (poora code)
              _fillFrom(index, value);
              return;
            }
            // Naya digit (agar box mein pehle se digit tha to 2 chars aate hain -> last wala lo)
            _controllers[index].text = value[value.length - 1];
            setState(() {});
            if (index < 5) {
              _focusNodes[index + 1].requestFocus();
            } else {
              _focusNodes[index].unfocus();
              _verifyOtp(); // last digit par auto-verify
            }
          },
        ),
      ),
    );
  }
}
