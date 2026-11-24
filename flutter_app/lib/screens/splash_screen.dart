import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

/// A 10-second kite intro (sunset sky, flying kites, logo reveal).
/// No video file / extra package needed - it is a pure Flutter animation.
/// You can move ahead at any time with the top-right "Skip".
/// After the intro: if there is a token -> Dashboard, otherwise -> Login.
/// (After login the Team screen comes, its Skip -> Dashboard.)
class SplashScreen extends StatefulWidget {
  /// This callback is called when the app is ready (after the login check)
  /// — main.dart uses it to handle a deep-link pending invite
  final VoidCallback? onReady;
  const SplashScreen({super.key, this.onReady});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _introDuration = Duration(seconds: 10);

  late final AnimationController _c;
  late final _SkyPainter _painter;
  late final Future<bool> _loggedInFuture;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _loggedInFuture = AuthService.isLoggedIn();
    _c = AnimationController(vsync: this, duration: _introDuration);
    _painter = _SkyPainter(_c);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _goNext();
    });
    _c.forward();
  }

  Future<void> _goNext() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    final loggedIn = await _loggedInFuture;
    if (!mounted) return;

    // The following screens are light -> status bar icons dark
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) =>
            loggedIn ? const DashboardScreen() : const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );

    // Callback for a deep-link pending invite
    widget.onReady?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // progress 0..1 of a portion (a..b) of t
  double _p(double a, double b, [Curve curve = Curves.easeOut]) =>
      Interval(a, b, curve: curve).transform(_c.value);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF2A0A4A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Animated sky + kites
            RepaintBoundary(child: CustomPaint(painter: _painter)),

            // Logo / text overlay
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => _buildOverlay(context),
              ),
            ),

            // Skip
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 16),
                  child: GestureDetector(
                    onTap: _goNext,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Skip',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded,
                              color: Colors.white, size: 11),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final logoP = _p(0.10, 0.26, Curves.easeOutBack);
    final titleP = _p(0.24, 0.38);
    final subP = _p(0.36, 0.48);
    final l1 = _p(0.52, 0.60);
    final l2 = _p(0.62, 0.70);
    final l3 = _p(0.72, 0.80);
    final fadeIn = 1 - _p(0.0, 0.06, Curves.linear);
    final fadeOut = _p(0.95, 1.0, Curves.linear);

    Widget tag(String text, double p) => Opacity(
          opacity: p.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - p) * 10),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: const Alignment(0, -0.1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: logoP.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * logoP,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const GulabiLogo(size: 64, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Opacity(
                opacity: titleP.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - titleP) * 16),
                  child: const Text(
                    'Gulabi Charkhi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 14)],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: subP.clamp(0.0, 1.0),
                child: const Text(
                  'Pink Spool • Kite Battle Arena',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(height: 34),
              tag('Fly high.', l1),
              const SizedBox(height: 8),
              tag('Cut the string.', l2),
              const SizedBox(height: 8),
              tag('Rule the sky.', l3),
            ],
          ),
        ),

        // Progress bar
        Positioned(
          left: 40,
          right: 40,
          bottom: 40 + MediaQuery.of(context).padding.bottom,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 3,
              color: Colors.white24,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _c.value.clamp(0.0, 1.0),
                child: Container(color: Colors.white),
              ),
            ),
          ),
        ),

        // Start: fade-in from black, End: fade-out to pink
        if (fadeIn > 0) Container(color: Colors.black.withValues(alpha: fadeIn)),
        if (fadeOut > 0)
          Container(color: AppColors.bgPink.withValues(alpha: fadeOut.clamp(0.0, 1.0))),
      ],
    );
  }
}

// ======================================================================
// Sky + kites painter
// ======================================================================
class _Kite {
  final double x, y; // base position (fraction of the screen)
  final double size; // fraction of the width
  final Color c1, c2;
  final double phase, amp, anchorX;
  const _Kite(this.x, this.y, this.size, this.c1, this.c2, this.phase, this.amp,
      this.anchorX);
}

class _SkyPainter extends CustomPainter {
  final AnimationController c;
  _SkyPainter(this.c) : super(repaint: c);

  static const _kites = <_Kite>[
    _Kite(0.50, 0.40, 0.17, Color(0xFF9B5BFF), Color(0xFFD9C4FF), 2.1, 0.05, 0.48),
    _Kite(0.20, 0.30, 0.13, Color(0xFFFF4FA3), Color(0xFFFFB3D6), 0.0, 0.04, 0.12),
    _Kite(0.80, 0.24, 0.11, Color(0xFFFFC93C), Color(0xFFFFF0B0), 1.3, 0.035, 0.88),
    _Kite(0.88, 0.52, 0.09, Color(0xFF3DDCFF), Color(0xFFC9F4FF), 3.0, 0.03, 0.95),
    _Kite(0.10, 0.58, 0.085, Color(0xFF7CFFB2), Color(0xFFD3FFE6), 4.2, 0.03, 0.05),
    _Kite(0.64, 0.13, 0.075, Colors.white, Color(0xFFFFD6EA), 5.0, 0.03, 0.70),
    _Kite(0.34, 0.12, 0.06, Color(0xFFFF8A5B), Color(0xFFFFD0B8), 0.7, 0.03, 0.30),
  ];

  static final List<Offset> _stars = List.generate(45, (i) {
    final r = math.Random(i * 7 + 3);
    return Offset(r.nextDouble(), r.nextDouble() * 0.55);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = c.value;
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // ---- Sky gradient ----
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2A0A4A),
            Color(0xFF7B2FBE),
            Color(0xFFE91E8C),
            Color(0xFFFF9AB8),
          ],
          stops: [0.0, 0.40, 0.75, 1.0],
        ).createShader(rect),
    );

    // ---- Stars ----
    final starPaint = Paint();
    for (var i = 0; i < _stars.length; i++) {
      final tw = 0.4 + 0.6 * math.sin(t * math.pi * 8 + i);
      starPaint.color =
          Colors.white.withValues(alpha: (0.55 * tw * (1 - t * 0.7)).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(_stars[i].dx * w, _stars[i].dy * h), 1.2, starPaint);
    }

    // ---- Sun (slowly rises) ----
    final sunC = Offset(w * 0.5, h * (0.88 - 0.10 * t));
    final sunR = w * 0.36;
    canvas.drawCircle(
      sunC,
      sunR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE08A).withValues(alpha: 0.95),
            const Color(0xFFFF8FB3).withValues(alpha: 0.45),
            const Color(0x00FF8FB3),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: sunC, radius: sunR)),
    );

    // ---- Clouds ----
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.14);
    const clouds = [
      [0.18, 0.20, 1.0, 0.0],
      [0.55, 0.34, 1.4, 0.35],
      [0.85, 0.48, 0.8, 0.7],
      [0.30, 0.66, 1.2, 0.15],
    ];
    for (final cl in clouds) {
      final x = ((cl[0] + t * (0.10 + cl[2] * 0.06) + cl[3]) % 1.4 - 0.2) * w;
      _cloud(canvas, Offset(x, cl[1] * h), cl[2], cloudPaint);
    }

    // ---- Kites ----
    for (final k in _kites) {
      _drawKite(canvas, size, k, t);
    }
  }

  void _cloud(Canvas canvas, Offset c, double s, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 130 * s, height: 34 * s),
        Radius.circular(17 * s),
      ),
      p,
    );
    canvas.drawCircle(c + Offset(-22 * s, -14 * s), 22 * s, p);
    canvas.drawCircle(c + Offset(14 * s, -18 * s), 28 * s, p);
  }

  void _drawKite(Canvas canvas, Size size, _Kite k, double t) {
    final w = size.width, h = size.height;
    final s = w * k.size;

    // Position - gently waving + slowly rising
    final cx = (k.x + math.sin(t * math.pi * 4 + k.phase) * k.amp) * w;
    final cy =
        (k.y + math.cos(t * math.pi * 3 + k.phase) * k.amp * 0.6 - t * 0.03) * h;
    final angle = math.sin(t * math.pi * 6 + k.phase) * 0.22;

    // Bottom point (world coords) - the string starts here
    final bx = cx - math.sin(angle) * s * 0.8;
    final by = cy + math.cos(angle) * s * 0.8;

    // ---- String ----
    final anchor = Offset(k.anchorX * w, h * 1.02);
    final sway = math.sin(t * math.pi * 4 + k.phase) * w * 0.06;
    final ctrl = Offset((bx + anchor.dx) / 2 + sway, (by + anchor.dy) / 2);
    canvas.drawPath(
      Path()
        ..moveTo(bx, by)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, anchor.dx, anchor.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // ---- Kite body ----
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);

    // Tail
    final tail = Path()..moveTo(0, s * 0.8);
    for (var i = 1; i <= 18; i++) {
      final x = math.sin(i * 0.7 + t * math.pi * 8 + k.phase) * s * 0.14 * (i / 18);
      tail.lineTo(x, s * 0.8 + i * s * 0.085);
    }
    canvas.drawPath(
      tail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    final bow = Paint()..color = k.c1;
    for (var i = 4; i <= 18; i += 4) {
      final x = math.sin(i * 0.7 + t * math.pi * 8 + k.phase) * s * 0.14 * (i / 18);
      canvas.drawCircle(Offset(x, s * 0.8 + i * s * 0.085), s * 0.045, bow);
    }

    // Two-tone diamond
    final top = Offset(0, -s * 0.65);
    final bottom = Offset(0, s * 0.8);
    final left = Offset(-s * 0.5, -s * 0.1);
    final right = Offset(s * 0.5, -s * 0.1);

    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(bottom.dx, bottom.dy)
        ..close(),
      Paint()..color = k.c1,
    );
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(bottom.dx, bottom.dy)
        ..close(),
      Paint()..color = k.c2,
    );

    // Sticks
    final stick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.7);
    canvas.drawLine(top, bottom, stick);
    canvas.drawLine(left, right, stick);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) => false; // repaint is driven by the controller
}
