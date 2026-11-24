import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'dashboard_screen.dart';
import 'create_team_screen.dart';
import 'join_team_screen.dart';

/// "Get on a team to start battling" screen.
/// - Create a team  -> enter a name, become captain, share the invite code
/// - Join a team    -> via an invite code or the public team list
/// - Skip for now   -> straight to the Dashboard
///
/// If [fromDashboard] is true (opened from the Teams tab), Skip/Done only pops.
class TeamSetupScreen extends StatelessWidget {
  final bool fromDashboard;
  const TeamSetupScreen({super.key, this.fromDashboard = false});

  static const _bg = Color(0xFFFDE8F1);

  void _finish(BuildContext context, {bool joined = false}) {
    if (fromDashboard) {
      Navigator.pop(context, joined);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
    }
  }

  // Create / Join are now full screens. Once a team is created/joined, move ahead.
  Future<void> _open(BuildContext context, Widget screen) async {
    final team = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (team != null && context.mounted) {
      _finish(context, joined: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    SizedBox(height: constraints.maxHeight * 0.12),
                    const GulabiLogo(size: 52),
                    const SizedBox(height: 40),
                    const Text(
                      'Get on a team to start\nbattling',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Pick one — start your own crew or hop into\nsomeone else\'s.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: Color(0xFF55505A),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ---- Create a team ----
                    _ActionCard(
                      filled: true,
                      icon: Icons.add_rounded,
                      title: 'Create a team',
                      subtitle: "You're the captain — invite your friends.",
                      onTap: () => _open(context, const CreateTeamScreen()),
                    ),
                    const SizedBox(height: 14),

                    // ---- Join a team ----
                    _ActionCard(
                      filled: false,
                      icon: Icons.group_outlined,
                      title: 'Join a team',
                      subtitle: 'Browse public teams or use an invite code.',
                      onTap: () => _open(context, const JoinTeamScreen()),
                    ),

                    const Spacer(),

                    // ---- Skip ----
                    TextButton(
                      onPressed: () => _finish(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          color: Color(0xFF6B6570),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// Big action card
// ======================================================================
class _ActionCard extends StatelessWidget {
  final bool filled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.filled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = filled ? Colors.white : const Color(0xFF111111);
    final subColor = filled ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF6B6570);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFFEA3D97), Color(0xFFA64CF5)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: filled ? null : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (filled ? AppColors.primaryPink : Colors.black)
                  .withValues(alpha: filled ? 0.28 : 0.06),
              blurRadius: filled ? 18 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: filled
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFF1E4FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: filled ? Colors.white : const Color(0xFF8E3FD6),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(color: subColor, fontSize: 12.5, height: 1.25),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: filled ? Colors.white : const Color(0xFF8E3FD6),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
