import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/app_theme.dart';
import '../services/team_service.dart';
import '../widgets/team_widgets.dart';
import '../widgets/team_matches_tab.dart';
import 'create_team_screen.dart';

/// Team page.
/// For a member: Members | Scoreboard | Invite | Matches (+ captain actions)
/// For a non-member (public team): Members | Matches + "Join team" below.
/// On joining, it pops with the team map.
class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  Map<String, dynamic>? _team;
  List<Map<String, dynamic>> _requests = [];
  String? _error;
  bool _loading = true;
  bool _busy = false;
  int _tab = 0;

  bool get _isMember => _team?['isMember'] == true;
  bool get _isCaptain => _team?['isCaptain'] == true;
  String get _id => widget.teamId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await TeamService.detail(_id);
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _error = (res['message'] ?? 'Could not load team').toString();
        _loading = false;
      });
      return;
    }
    final team = TeamService.asMap(res['team']);
    List<Map<String, dynamic>> reqs = [];
    if (team?['isCaptain'] == true) {
      final r = await TeamService.requests(_id);
      reqs = TeamService.asList(r['requests']);
    }
    if (!mounted) return;
    setState(() {
      _team = team;
      _requests = reqs;
      _error = null;
      _loading = false;
      final maxTab = _tabLabels.length - 1;
      if (_tab > maxTab) _tab = maxTab;
    });
  }

  List<String> get _tabLabels =>
      _isMember
          ? ['Members', 'Scoreboard', 'Invite', 'Matches']
          : ['Members', 'Scoreboard', 'Matches'];
  List<IconData> get _tabIcons => _isMember
      ? [Icons.group_outlined, Icons.bar_chart_rounded, Icons.share_outlined, Icons.sports_score_rounded]
      : [Icons.group_outlined, Icons.bar_chart_rounded, Icons.sports_score_rounded];

  // Run an action; if the response contains a team, update the screen
  Future<bool> _run(Future<Map<String, dynamic>> Function() fn, {String? okMessage}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final res = await fn();
    if (!mounted) return false;
    setState(() => _busy = false);
    if (res['success'] != true) {
      AppUi.snack(context, res['message'] ?? 'Something went wrong', error: true);
      return false;
    }
    if (okMessage != null || res['message'] != null) {
      AppUi.snack(context, okMessage ?? res['message'].toString());
    }
    await _load(silent: true);
    return true;
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await TeamService.join(teamId: _id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] != true) {
      AppUi.snack(context, res['message'] ?? 'Could not join team', error: true);
      return;
    }
    AppUi.snack(context, res['message'] ?? 'Done');
    if (res['joined'] == true) {
      Navigator.pop(context, TeamService.asMap(res['team']));
    } else {
      _load(silent: true);
    }
  }

  Future<void> _leave() async {
    final ok = await confirmDialog(context,
        title: 'Leave team?',
        message: 'You will no longer be part of ${_team?['name']}.',
        confirmText: 'Leave');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await TeamService.leave();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      AppUi.snack(context, res['message'] ?? 'You left the team');
      Navigator.pop(context);
    } else {
      AppUi.snack(context, res['message'] ?? 'Could not leave team', error: true);
    }
  }

  Future<void> _disband() async {
    final ok = await confirmDialog(context,
        title: 'Disband team?',
        message: 'This removes ${_team?['name']} and frees all members. This cannot be undone.',
        confirmText: 'Disband');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await TeamService.disband(_id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      AppUi.snack(context, 'Team disbanded');
      Navigator.pop(context);
    } else {
      AppUi.snack(context, res['message'] ?? 'Could not disband team', error: true);
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => CreateTeamScreen(existing: _team)),
    );
    if (updated != null) _load(silent: true);
  }

  Future<void> _regenerate() async {
    final ok = await confirmDialog(context,
        title: 'New invite code?',
        message: 'The old code and QR will stop working immediately.',
        confirmText: 'Generate');
    if (!ok) return;
    await _run(() => TeamService.regenerateCode(_id));
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppUi.snack(context, '$label copied');
  }

  // ======================================================================
  @override
  Widget build(BuildContext context) {
    final t = _team;
    return Scaffold(
      backgroundColor: kTeamPageBg,
      body: _loading
          ? const Column(children: [
              GradientHeader(title: 'Team'),
              Expanded(
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink))),
            ])
          : (t == null ? _errorView() : _content(t)),
    );
  }

  Widget _errorView() {
    return Column(
      children: [
        const GradientHeader(title: 'Team'),
        Expanded(
          child: Center(
            child: EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Cannot open this team',
              message: _error ?? 'Something went wrong',
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(Map<String, dynamic> t) {
    final name = (t['name'] ?? '').toString();
    return Column(
      children: [
        GradientHeader(
          title: name,
          subtitle: (t['region'] ?? '').toString(),
          actions: [if (_isMember) _menu()],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryPink,
            onRefresh: () => _load(silent: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _identity(t),
                const SizedBox(height: 14),
                PillTabs(
                  labels: _tabLabels,
                  icons: _tabIcons,
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 12),
                _tabBody(t),
              ],
            ),
          ),
        ),
        _bottomBar(t),
      ],
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      onSelected: (v) {
        if (v == 'edit') _edit();
        if (v == 'leave') _leave();
        if (v == 'disband') _disband();
      },
      itemBuilder: (_) => [
        if (_isCaptain) const PopupMenuItem(value: 'edit', child: Text('Edit team')),
        if (!_isCaptain) const PopupMenuItem(value: 'leave', child: Text('Leave team')),
        if (_isCaptain)
          const PopupMenuItem(
            value: 'disband',
            child: Text('Disband team', style: TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }

  Widget _identity(Map<String, dynamic> t) {
    final name = (t['name'] ?? '').toString();
    final tag = (t['tag'] ?? '').toString();
    final about = (t['about'] ?? '').toString();
    return WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TeamAvatar(name: name, tag: tag, logo: t['logo']?.toString(), size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (tag.isNotEmpty)
                          MiniPill(tag, fg: AppColors.primaryPink, bg: const Color(0xFFFCE4F1)),
                        t['isPublic'] == true
                            ? const MiniPill('Public', fg: Color(0xFF15803D), bg: Color(0xFFDCFCE7))
                            : const MiniPill('Private', fg: Color(0xFF6B21A8), bg: Color(0xFFF3E8FF)),
                        StatusPill(full: t['status'] == 'full'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (about.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(about,
                style: const TextStyle(fontSize: 13, height: 1.35, color: Color(0xFF55505A))),
          ],
        ],
      ),
    );
  }

  Widget _tabBody(Map<String, dynamic> t) {
    final label = _tabLabels[_tab];
    switch (label) {
      case 'Scoreboard':
        return _scoreboard(t);
      case 'Invite':
        return _invite(t);
      case 'Matches':
        return TeamMatchesTab(key: ValueKey('matches-$_id'), teamId: _id);
      default:
        return _members(t);
    }
  }

  // ---------------- Members ----------------
  Widget _members(Map<String, dynamic> t) {
    final members = TeamService.asList(t['members']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isCaptain && _requests.isNotEmpty) ...[
          SectionLabel('Join requests (${_requests.length})'),
          ..._requests.map(_requestRow),
          const SizedBox(height: 4),
        ],
        SectionLabel('Members (${t['memberCount']}/${t['maxMembers']})'),
        WhiteCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              for (int i = 0; i < members.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFF1E7EE)),
                _memberRow(members[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatarCircle(String name, {double size = 38}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFA64CF5), Color(0xFF7B2FBE)]),
        ),
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42),
        ),
      );

  Widget _memberRow(Map<String, dynamic> m) {
    final isCap = m['isCaptain'] == true;
    final name = (m['name'] ?? '').toString();
    final city = (m['city'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _avatarCircle(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.textDark)),
                if (city.isNotEmpty)
                  Text(city, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
              ],
            ),
          ),
          if (isCap) const MiniPill('Captain', fg: AppColors.primaryPink, bg: Color(0xFFFCE4F1)),
          if (_isCaptain && !isCap)
            PopupMenuButton<String>(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textGrey, size: 20),
              onSelected: (v) async {
                final uid = m['id'].toString();
                if (v == 'captain') {
                  final ok = await confirmDialog(context,
                      title: 'Make $name captain?',
                      message: 'You will become a regular member.',
                      confirmText: 'Transfer');
                  if (ok) _run(() => TeamService.transferCaptain(_id, uid));
                } else {
                  final ok = await confirmDialog(context,
                      title: 'Remove $name?',
                      message: '$name will be removed from the team.',
                      confirmText: 'Remove');
                  if (ok) _run(() => TeamService.removeMember(_id, uid));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'captain', child: Text('Make captain')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from team', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _requestRow(Map<String, dynamic> r) {
    final uid = r['userId'].toString();
    final name = (r['name'] ?? '').toString();
    final city = (r['city'] ?? '').toString();
    return WhiteCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          _avatarCircle(name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text(city.isEmpty ? 'wants to join' : '$city • wants to join',
                    style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
              ],
            ),
          ),
          IconButton(
            onPressed: _busy ? null : () => _run(() => TeamService.reject(_id, uid)),
            icon: const Icon(Icons.close_rounded, color: AppColors.error),
          ),
          IconButton(
            onPressed: _busy ? null : () => _run(() => TeamService.approve(_id, uid)),
            icon: const Icon(Icons.check_circle_rounded, color: AppColors.success),
          ),
        ],
      ),
    );
  }

  // ---------------- Scoreboard ----------------
  Widget _scoreboard(Map<String, dynamic> t) {
    final s = TeamService.asMap(t['scoreboard']) ?? {};
    int n(String k) => (s[k] is num) ? (s[k] as num).toInt() : 0;
    final played = n('played');
    final scored = n('cutsScored');
    final conceded = n('cutsConceded');
    final total = scored + conceded;
    final form = (s['recentForm'] is List) ? List.from(s['recentForm']) : [];
    final players = TeamService.asList(t['members']);

    Widget tile(String v, String label, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                Text(v, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 2),
                Text(label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9.5, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: AppColors.textGrey)),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tile('$played', 'Played', AppColors.textDark),
            tile('${n('wins')}', 'Wins', const Color(0xFF16A34A)),
            tile('${n('losses')}', 'Losses', AppColors.primaryPink),
            tile('${n('ties')}', 'Ties', const Color(0xFF8E3FD6)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 0, 0),
          child: Text('Win rate ${n('winRate')}% across $played matches',
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
        ),
        const SectionLabel('Cuts'),
        WhiteCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$scored',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primaryPink)),
                      const Text('scored', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$conceded',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF8E3FD6))),
                      const Text('conceded', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : scored / total,
                  minHeight: 7,
                  color: AppColors.primaryPink,
                  backgroundColor: const Color(0xFFE9D5FB),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel('Recent form'),
        Row(
          children: List.generate(5, (i) {
            final v = i < form.length ? form[i] : null;
            Color bg = const Color(0xFFF0EAF0);
            Color fg = AppColors.textGrey;
            if (v == 'W') {
              bg = const Color(0xFFDCFCE7);
              fg = const Color(0xFF15803D);
            } else if (v == 'L') {
              bg = const Color(0xFFFEE2E2);
              fg = AppColors.error;
            } else if (v == 'T') {
              bg = const Color(0xFFF3E8FF);
              fg = const Color(0xFF8E3FD6);
            }
            return Expanded(
              child: Container(
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: Text(v?.toString() ?? '—',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
              ),
            );
          }),
        ),
        const SectionLabel('Players'),
        WhiteCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            children: [
              const Row(
                children: [
                  Expanded(
                      child: Text('PLAYER',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textGrey))),
                  SizedBox(
                      width: 44,
                      child: Text('MP',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textGrey))),
                  SizedBox(
                      width: 52,
                      child: Text('CUTS',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textGrey))),
                ],
              ),
              const Divider(height: 14, color: Color(0xFFF1E7EE)),
              for (final p in players)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      _avatarCircle((p['name'] ?? '').toString(), size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text((p['name'] ?? '').toString(),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                      SizedBox(
                          width: 44,
                          child: Text('${p['matchesPlayed'] ?? 0}', textAlign: TextAlign.center)),
                      SizedBox(
                        width: 52,
                        child: Text('${p['cuts'] ?? 0}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, color: AppColors.primaryPink)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- Invite ----------------
  Widget _invite(Map<String, dynamic> t) {
    final code = (t['inviteCode'] ?? '').toString();
    final link = (t['inviteLink'] ?? '').toString();
    final qr = (t['qrData'] ?? link).toString();

    Widget copyRow(String label, String value, {double? letterSpacing}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(label),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFCEFF6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: letterSpacing == null ? 12.5 : 20,
                        letterSpacing: letterSpacing,
                        fontWeight: FontWeight.w800,
                        color: letterSpacing == null ? AppColors.textDark : AppColors.primaryPink,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: value.isEmpty ? null : () => _copy(value, label),
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copy'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primaryPurple),
                  ),
                ],
              ),
            ),
          ],
        );

    return WhiteCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text('SCAN TO JOIN',
                style: TextStyle(
                    fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Color(0xFF6B6570))),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF1E7EE)),
              ),
              child: qr.isEmpty
                  ? const SizedBox(width: 190, height: 190)
                  : QrImageView(data: qr, size: 190, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text((t['name'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          Center(
            child: Text((t['region'] ?? '').toString(),
                style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
          ),
          copyRow('Invite code', code, letterSpacing: 4),
          copyRow('Invite link', link),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: code.isEmpty
                ? null
                : () => _copy(
                      'Join my team on the Gulabi Charkhi app: "${(t['name'] ?? '').toString()}" '
                      '\n\nOpen the app > Join Team > enter this code: $code'
                      '${link.isEmpty ? '' : '\n\nLink: $link'}',
                      'Invite message'),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Copy invite message'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryPurple),
          ),
          if (_isCaptain) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _busy ? null : _regenerate,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Generate new code'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryPink),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- Bottom bar ----------------
  Widget _bottomBar(Map<String, dynamic> t) {
    if (_isMember) return const SizedBox.shrink();
    final full = t['status'] == 'full';
    final requested = t['requested'] == true;

    Widget btn;
    if (requested) {
      btn = OutlinedButton(
        onPressed: _busy
            ? null
            : () async {
                await TeamService.cancelRequest(_id);
                _load(silent: true);
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryPink,
          side: const BorderSide(color: AppColors.primaryPink),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Text('Request sent • Tap to cancel'),
      );
    } else if (full) {
      btn = const Opacity(
        opacity: 0.5,
        child: const GradientButton(text: 'Team is full', onPressed: null),
      );
    } else {
      btn = GradientButton(text: 'Join team', isLoading: _busy, onPressed: _join);
    }
    return SafeArea(
      top: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 12), child: btn),
    );
  }
}
