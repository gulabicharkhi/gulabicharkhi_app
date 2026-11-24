import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/match_detail_screen.dart';
import 'services/team_service.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';

// Use the app_links package for deep link handling:
// Add to pubspec.yaml:
//   app_links: ^6.3.2

// Also add this to pubspec.yaml (for FCM):
//   firebase_core: ^3.6.0
//   firebase_messaging: ^15.1.3
//   flutter_local_notifications: ^18.0.1

// ══════════════════════════════════════════════════════════════════════════
// Deep link format:  gulabicharkhi://join/RHVJWH
//                    https://api.yourdomain.com/join/RHVJWH  (web fallback)
// ══════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set up FCM + local notifications
  await NotificationService.init();

  runApp(const GulabiCharkhiApp());
}

class GulabiCharkhiApp extends StatefulWidget {
  const GulabiCharkhiApp({super.key});

  @override
  State<GulabiCharkhiApp> createState() => _GulabiCharkhiAppState();
}

class _GulabiCharkhiAppState extends State<GulabiCharkhiApp> {
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription? _linkSub;

  // Pending invite code — if the app was closed and opened via a link
  String? _pendingInviteCode;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _setupFcmNavigation();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  // ── FCM notification tap → navigate to the screen ───────────────────────
  void _setupFcmNavigation() {
    NotificationService.onTap = (data) {
      final refType = data['refType'] ?? '';
      final refId   = data['refId']   ?? '';

      if (refType == 'Battle' && refId.isNotEmpty) {
        final nav = _navKey.currentState;
        if (nav == null) return;
        nav.push(MaterialPageRoute(
          builder: (_) => MatchDetailScreen(matchId: refId),
        ));
      }
      // You can add more types:
      // else if (refType == 'Team') { ... }
      // else if (refType == 'Tournament') { ... }
    };
  }

  Future<void> _initDeepLinks() async {
    // ── uncomment the app_links package once it is installed ──────────────
    //
    // final appLinks = AppLinks();
    //
    // // The app was closed, opened via a link (cold start)
    // try {
    //   final uri = await appLinks.getInitialLink();
    //   if (uri != null) _handleLink(uri);
    // } catch (_) {}
    //
    // // The app is already running, a link arrived (warm start)
    // _linkSub = appLinks.uriLinkStream.listen(
    //   _handleLink,
    //   onError: (_) {},
    // );
  }

  void _handleLink(Uri uri) {
    // gulabicharkhi://join/RHVJWH  or  https://domain.com/join/RHVJWH
    final segments = uri.pathSegments;
    final joinIdx  = segments.indexOf('join');
    if (joinIdx == -1 || joinIdx + 1 >= segments.length) return;

    final code = segments[joinIdx + 1].toUpperCase().trim();
    if (code.isEmpty) return;

    // Is the Navigator ready?
    final nav = _navKey.currentState;
    if (nav == null) {
      // Splash is still running — store it, it will be handled later
      setState(() => _pendingInviteCode = code);
      return;
    }
    _openJoinWithCode(nav, code);
  }

  void _openJoinWithCode(NavigatorState nav, String code) {
    nav.push(MaterialPageRoute(
      builder: (_) => _InviteCodeLandingScreen(inviteCode: code),
    ));
  }

  /// SplashScreen calls this callback after login —
  /// then check for a pending invite
  void _onAppReady() {
    final code = _pendingInviteCode;
    if (code == null) return;
    setState(() => _pendingInviteCode = null);
    final nav = _navKey.currentState;
    if (nav != null) _openJoinWithCode(nav, code);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gulabi Charkhi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: _navKey,
      home: SplashScreen(onReady: _onAppReady),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Invite Code Landing Screen
// When someone opens a /join/CODE link:
//   → Find the team from the backend
//   → Confirm dialog → Join
// ════════════════════════════════════════════════════════════════════════════
class _InviteCodeLandingScreen extends StatefulWidget {
  final String inviteCode;
  const _InviteCodeLandingScreen({required this.inviteCode});

  @override
  State<_InviteCodeLandingScreen> createState() => _InviteCodeLandingScreenState();
}

class _InviteCodeLandingScreenState extends State<_InviteCodeLandingScreen> {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  bool _loading = true;
  bool _joining = false;
  Map<String, dynamic>? _team;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    setState(() { _loading = true; _error = null; });
    final res = await TeamService.findByCode(widget.inviteCode);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _team = TeamService.asMap(res['team']);
      } else {
        _error = (res['message'] ?? 'Team not found').toString();
      }
    });
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    final res = await TeamService.join(inviteCode: widget.inviteCode);
    if (!mounted) return;
    setState(() => _joining = false);

    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text((res['message'] ?? (ok ? 'Team joined!' : 'Could not join')).toString()),
      backgroundColor: ok ? const Color(0xFF15803D) : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
    if (ok) Navigator.pop(context, TeamService.asMap(res['team']));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // Back button
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : _error != null
                          ? _errorCard()
                          : _teamCard(),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _teamCard() {
    if (_team == null) return const SizedBox();
    final name   = (_team!['name']   ?? '').toString();
    final tag    = (_team!['tag']    ?? '').toString();
    final region = (_team!['region'] ?? _team!['city'] ?? '').toString();
    final count  = _team!['memberCount'] ?? 0;
    final max    = _team!['maxMembers']  ?? 10;
    final isFull = _team!['status'] == 'full';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(children: [
        // Avatar
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE93D95), Color(0xFFA64CF5)]),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Text(
            tag.length > 3 ? tag.substring(0, 3) : tag,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ),
        const SizedBox(height: 14),

        // Team name
        Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 4),

        // Location + members
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (region.isNotEmpty) ...[
            const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF999999)),
            const SizedBox(width: 3),
            Text(region, style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
            const Text('  ·  ', style: TextStyle(color: Color(0xFF999999))),
          ],
          const Icon(Icons.group_outlined, size: 14, color: Color(0xFF999999)),
          const SizedBox(width: 3),
          Text('$count/$max', style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
        ]),
        const SizedBox(height: 6),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isFull ? const Color(0xFFFFEDED) : const Color(0xFFE6FAF0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isFull ? 'Team Full' : 'Open to Join',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isFull ? Colors.redAccent : const Color(0xFF15803D),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Invite code display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFDE8F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.inviteCode,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900,
                letterSpacing: 7, color: _pink),
          ),
        ),
        const SizedBox(height: 20),

        // Join button
        if (!isFull)
          GestureDetector(
            onTap: _joining ? null : _join,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_pink, _purple]),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _joining
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                  : const Text('Join Team 🪁',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          )
        else
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('Team is full',
                style: TextStyle(color: Color(0xFF999999),
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),

        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF999999))),
        ),
      ]),
    );
  }

  Widget _errorCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(children: [
        const Icon(Icons.link_off_rounded, size: 56, color: Color(0xFFCCCCCC)),
        const SizedBox(height: 14),
        const Text('The link did not work',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Text(
          _error ?? 'The invite code is wrong or has expired.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF888888), height: 1.4),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _lookup,
          child: Container(
            width: double.infinity, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_pink, _purple]),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('Try again',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Go back', style: TextStyle(color: Color(0xFF999999))),
        ),
      ]),
    );
  }
}
