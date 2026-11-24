import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/team_service.dart';
import '../widgets/team_widgets.dart';
import 'create_team_screen.dart';
import 'join_team_screen.dart';
import 'team_detail_screen.dart';

/// "Teams" screen: Join / Create cards + MY TEAMS list.
/// Dashboard ke Teams tab mein embed hota hai (showBack: false).
class TeamsHubScreen extends StatefulWidget {
  final bool showBack;
  final double bottomPadding; // dashboard ke bottom nav ke liye jagah
  final VoidCallback? onChanged; // team join / create / leave hone par

  const TeamsHubScreen({
    super.key,
    this.showBack = false,
    this.bottomPadding = 24,
    this.onChanged,
  });

  @override
  State<TeamsHubScreen> createState() => _TeamsHubScreenState();
}

class _TeamsHubScreenState extends State<TeamsHubScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _pending = [];

  bool get _hasTeam => _teams.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await TeamService.mine();
    if (!mounted) return;
    setState(() {
      if (res['success'] == true) {
        _teams = TeamService.asList(res['teams']);
        _pending = TeamService.asList(res['pendingRequests']);
      }
      _loading = false;
    });
  }

  Future<void> _go(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    await _load(silent: true);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTeamPageBg,
      body: Column(
        children: [
          GradientHeader(
            title: 'Teams',
            subtitle: 'Form your kite battle squad',
            showBack: widget.showBack,
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryPink,
              onRefresh: () => _load(silent: true),
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 6, 16, widget.bottomPadding),
                children: [
                  const SectionLabel('Get started'),
                  // Ek user ek hi team mein ho sakta hai - team hai to ye cards disable
                  _actionCard(
                    filled: false,
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Join a Team',
                    subtitle: 'Browse, scan a QR, or enter an invite code',
                    colors: const [Color(0xFF8B5CF6), Color(0xFFA64CF5)],
                    onTap: _hasTeam
                        ? () => AppUi.snack(context, 'You are already in a team. Leave it first to join another.', error: true)
                        : () => _go(const JoinTeamScreen()),
                  ),
                  const SizedBox(height: 10),
                  _actionCard(
                    filled: true,
                    icon: Icons.add_circle_outline_rounded,
                    title: 'Create your Team',
                    subtitle: 'Start your own squad and invite players',
                    colors: const [Color(0xFFEA3D97), Color(0xFFE91E63)],
                    onTap: _hasTeam
                        ? () => AppUi.snack(context, 'You are already in a team. Leave it first to create another.', error: true)
                        : () => _go(const CreateTeamScreen()),
                  ),
                  SectionLabel('My teams',
                      trailing: Text('${_teams.length} ${_teams.length == 1 ? 'team' : 'teams'}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textGrey))),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
                    )
                  else if (_teams.isEmpty)
                    const WhiteCard(
                      child: EmptyState(
                        icon: Icons.groups_outlined,
                        title: 'No teams yet',
                        message: 'Join an existing team or create your own to start battling.',
                      ),
                    )
                  else
                    ..._teams.map((t) => TeamRow(
                          team: t,
                          onTap: () => _go(TeamDetailScreen(teamId: t['id'].toString())),
                          trailing: t['isCaptain'] == true
                              ? const MiniPill('Captain', fg: AppColors.primaryPink, bg: Color(0xFFFCE4F1))
                              : const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
                        )),
                  if (_pending.isNotEmpty) ...[
                    const SectionLabel('Pending requests'),
                    ..._pending.map((t) => TeamRow(
                          team: t,
                          onTap: () => _go(TeamDetailScreen(teamId: t['id'].toString())),
                          trailing: SmallPinkButton(
                            text: 'Cancel',
                            onTap: () async {
                              await TeamService.cancelRequest(t['id'].toString());
                              _load(silent: true);
                            },
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required bool filled,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    final dim = _hasTeam;
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
