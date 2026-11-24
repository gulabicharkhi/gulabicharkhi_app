import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors - from screenshots
  static const Color bgPink = Color(0xFFFCE4EC);       // Light pink background
  static const Color primaryPink = Color(0xFFE91E8C);  // Hot pink
  static const Color primaryPurple = Color(0xFF7B2FBE); // Purple
  static const Color accentPink = Color(0xFFFF4081);   // Accent pink
  
  // Gradient colors
  static const Color gradientStart = Color(0xFFE91E8C); // Pink
  static const Color gradientEnd = Color(0xFF7B2FBE);   // Purple
  
  // Input field colors
  static const Color inputBg = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFF8BBD0);
  
  // Text colors
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textGrey = Color(0xFF9E9E9E);
  static const Color textPink = Color(0xFFE91E8C);
  
  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFF9800);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgPink,
      fontFamily: 'SF Pro Display',
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryPink,
        secondary: AppColors.primaryPurple,
        surface: AppColors.bgPink,
        error: AppColors.error,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryPink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          minimumSize: const Size(double.infinity, 54),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// Gradient button widget
class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPink.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}


// ------------------------------------------------------------------
// Gulabi Charkhi "G" logo (screenshots wala: beech mein G, dono side line)
// ------------------------------------------------------------------
class GulabiLogo extends StatelessWidget {
  final double size;
  final Color color;
  const GulabiLogo({super.key, this.size = 48, this.color = AppColors.primaryPink});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.7,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _LogoLinesPainter(color))),
          Container(
            width: size * 0.78,
            height: size * 0.78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: size * 0.07),
            ),
            child: Text(
              'G',
              style: TextStyle(
                color: color,
                fontSize: size * 0.48,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoLinesPainter extends CustomPainter {
  final Color color;
  _LogoLinesPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.height * 0.06
      ..strokeCap = StrokeCap.round;
    final cy = size.height / 2;
    // left & right thread lines
    canvas.drawLine(Offset(0, cy), Offset(size.width * 0.18, cy), p);
    canvas.drawLine(Offset(size.width * 0.82, cy), Offset(size.width, cy), p);
    // small end ticks
    final tick = size.height * 0.16;
    canvas.drawLine(Offset(0, cy - tick), Offset(0, cy + tick), p);
    canvas.drawLine(Offset(size.width, cy - tick), Offset(size.width, cy + tick), p);
  }

  @override
  bool shouldRepaint(covariant _LogoLinesPainter old) => old.color != color;
}

// ------------------------------------------------------------------
// Common SnackBar helper
// ------------------------------------------------------------------
class AppUi {
  static void snack(BuildContext context, String msg,
      {bool error = false, Duration duration = const Duration(seconds: 4)}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: duration,
          backgroundColor: error ? AppColors.error : AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
  }
}
