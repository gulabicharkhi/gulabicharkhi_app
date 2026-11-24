import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/battle_service.dart';
import '../widgets/team_widgets.dart';
import 'match_detail_screen.dart';

/// Battle Arena — Captain ka control center
///
/// Flow:
///   1. Captain → kisi team ko Challenge bhejo (venue + schedule optional)
///   2. Opponent captain → Incoming card pe Accept ya Decline
///   3. Dono captains → "Start Battle" dabate hain → LIVE
///   4. LIVE match → MatchDetailScreen
class BattleArenaScreen extends StatefulWidget {
  const BattleArenaScreen({super.key});

  @override
  State<BattleArenaScreen> createState() => _BattleArenaScreenState();
}

class _BattleArenaScreenState extends State<BattleArenaScreen> {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _busy    = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await BattleService.arena();
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _error   = (res['message'] ?? 'Arena load nahi hua').toString();
        _loading = false;
      });
      return;
    }
    setState(() { _data = res; _error = null; _loading = false; });
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.redAccent : const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(14),
      ));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = res['success'] == true;
    _toast((res['message'] ?? (ok ? 'Done!' : 'Kuch galat hua')).toString(),
        error: !ok);
    if (ok) await _load(silent: true);
  }

  void _openBattle(Map<String, dynamic> b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              MatchDetailScreen(matchId: b['id'].toString())),
    );
    if (mounted) _load(silent: true);
  }

  // ── challenge dialog ─────────────────────────────────────────────────────
  Future<void> _challengeDialog(Map<String, dynamic> team) async {
    // Controllers ab sheet ke andar bante/dispose hote hain (crash fix)
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChallengeSheet(
        teamName: (team['name'] ?? '').toString(),
      ),
    );

    if (result == null || !mounted) return;

    final pickedDate = result['date'] as DateTime?;
    final pickedTime = result['time'] as TimeOfDay?;
    DateTime? scheduledAt;
    if (pickedDate != null) {
      final t = pickedTime ?? const TimeOfDay(hour: 10, minute: 0);
      scheduledAt = DateTime(
          pickedDate.year, pickedDate.month, pickedDate.day, t.hour, t.minute);
    }

    await _run(() => BattleService.challenge(
          opponentTeamId: (team['id'] ?? '').toString(),
          venue:       (result['venue'] ?? '').toString(),
          area:        (result['area']  ?? '').toString(),
          scheduledAt: scheduledAt,
        ));
  }

  // ── decline dialog ───────────────────────────────────────────────────────
  Future<void> _declineDialog(Map<String, dynamic> battle) async {
    // null = cancel, warna reason string (empty bhi ho sakti hai)
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _DeclineDialog(),
    );
    if (reason == null || !mounted) return;
    await _run(
        () => BattleService.reject(battle['id'].toString(), reason: reason));
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDEBF4),
      body: Column(children: [
        _buildHeader(),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _buildHeader() {
    final team = _data?['myTeam'] is Map
        ? Map<String, dynamic>.from(_data!['myTeam'] as Map)
        : null;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 10, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.maybePop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Battle Arena 🪁',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            Text(
              team != null
                  ? (team['name'] ?? '').toString()
                  : 'Challenge, accept aur start karo',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ]),
        ),
        // Refresh
        GestureDetector(
          onTap: () => _load(),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle),
            child: const Icon(Icons.refresh_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _pink));
    }
    if (_error != null) {
      return _centred(Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 60, color: Color(0xFFCCCCCC)),
        const SizedBox(height: 10),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9E9E9E))),
        const SizedBox(height: 14),
        OutlinedButton(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
                foregroundColor: _pink,
                side: const BorderSide(color: _pink)),
            child: const Text('Retry')),
      ]));
    }

    final d = _data!;

    if (d['hasTeam'] != true) {
      return _centred(_infoCard(Icons.groups_rounded, 'Team chahiye',
          'Battle ke liye pehle Teams tab se team banao ya join karo.'));
    }
    if (d['isCaptain'] != true) {
      return _centred(_infoCard(Icons.shield_rounded, 'Sirf captain',
          'Challenge bhejna / accept karna sirf team captain kar sakta hai.'));
    }

    final incoming = BattleService.asList(d['incoming']);
    final outgoing = BattleService.asList(d['outgoing']);
    final active   = BattleService.asList(d['active']);
    final ready    = BattleService.asList(d['readyOpponents']);

    return RefreshIndicator(
      color: _pink,
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          // ── INCOMING ─────────────────────────────────────────────────────
          if (incoming.isNotEmpty) ...[
            _sectionLabel(
                '🔔 Incoming challenges', incoming.length, const Color(0xFF8E3FD6)),
            ...incoming.map(_incomingCard),
            const SizedBox(height: 6),
          ],

          // ── ACTIVE ───────────────────────────────────────────────────────
          if (active.isNotEmpty) ...[
            _sectionLabel('⚔️ Active battles', active.length, const Color(0xFF15803D)),
            ...active.map(_activeCard),
            const SizedBox(height: 6),
          ],

          // ── OUTGOING ─────────────────────────────────────────────────────
          if (outgoing.isNotEmpty) ...[
            _sectionLabel('📤 Sent challenges', outgoing.length, const Color(0xFFB45309)),
            ...outgoing.map(_outgoingCard),
            const SizedBox(height: 6),
          ],

          // ── READY TEAMS ──────────────────────────────────────────────────
          _sectionLabel('🏹 Teams to challenge', ready.length, const Color(0xFFE93D95)),
          if (ready.isEmpty)
            _infoCard(Icons.sports_score_rounded, 'Koi team available nahi',
                'Abhi koi aur public team nahi hai jise challenge kiya ja sake.'),
          ...ready.map(_teamCard),
        ],
      ),
    );
  }

  // ── card widgets ─────────────────────────────────────────────────────────

  Widget _incomingCard(Map<String, dynamic> b) {
    final ct = _m(b['challengerTeam']);
    final when = _fmtWhen(b['scheduledAt'] ?? b['challengedAt']);
    return _card(
      team: ct,
      topTag: _tag('INCOMING', const Color(0xFF8E3FD6)),
      name: (ct['name'] ?? '').toString(),
      sub: 'Aapko battle challenge kiya hai',
      info: when,
      venue: _venue(b),
      onTap: () => _openBattle(b),
      bottom: Row(children: [
        Expanded(
          child: _outlineBtn('Decline', Icons.close_rounded,
              _busy ? null : () => _declineDialog(b),
              color: Colors.redAccent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _filledBtn('Accept ✓', Icons.check_rounded,
              _busy ? null : () => _run(() => BattleService.accept(b['id'].toString()))),
        ),
      ]),
    );
  }

  Widget _activeCard(Map<String, dynamic> b) {
    final isLive = b['status'] == 'live';
    final oppKey = b['myRole'] == 'challenger' ? 'opponentTeam' : 'challengerTeam';
    final ct = _m(b[oppKey]);
    return _card(
      team: ct,
      topTag: _tag(isLive ? '🔴 LIVE' : 'ACCEPTED',
          isLive ? const Color(0xFFEF4444) : const Color(0xFF15803D)),
      name: (ct['name'] ?? '').toString(),
      sub: isLive
          ? 'Match chal raha hai — score dekhne ke liye tap karo'
          : 'Accepted — dono captains "Start Battle" dabayein',
      venue: _venue(b),
      onTap: () => _openBattle(b),
      bottom: isLive
          ? _filledBtn('Open Match →', Icons.arrow_forward_rounded,
              () => _openBattle(b))
          : _filledBtn('Start Battle ▶', Icons.play_arrow_rounded,
              _busy
                  ? null
                  : () => _run(() => BattleService.ready(b['id'].toString()))),
    );
  }

  Widget _outgoingCard(Map<String, dynamic> b) {
    final ct = _m(b['opponentTeam']);
    final when = _fmtWhen(b['scheduledAt'] ?? b['challengedAt']);
    return _card(
      team: ct,
      topTag: _tag('PENDING', const Color(0xFFB45309)),
      name: (ct['name'] ?? '').toString(),
      sub: 'Unke captain ke accept karne ka wait hai…',
      info: when,
      venue: _venue(b),
      onTap: () => _openBattle(b),
      bottom: _outlineBtn('Challenge cancel karo', Icons.close_rounded,
          _busy ? null : () => _run(() => BattleService.cancel(b['id'].toString()))),
    );
  }

  Widget _teamCard(Map<String, dynamic> t) {
    final region = (t['region'] ?? '').toString();
    final cnt    = '${t['memberCount'] ?? 0}/${t['maxMembers'] ?? 10} players';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(children: [
          _avatar(t, 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((t['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              Text(
                [if (region.isNotEmpty) region, cnt].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF9E9E9E)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          _filledBtn('Challenge 🪁', Icons.sports_kabaddi_rounded,
              _busy ? null : () => _challengeDialog(t),
              small: true),
        ]),
      ),
    );
  }

  // ── generic card ─────────────────────────────────────────────────────────
  Widget _card({
    required Map<String, dynamic> team,
    required Widget topTag,
    required String name,
    required String sub,
    String? info,
    String? venue,
    required VoidCallback onTap,
    required Widget bottom,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                _avatar(team, 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        topTag,
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A1A))),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFF9E9E9E))),
                      if (venue != null && venue.isNotEmpty)
                        Row(children: [
                          const Icon(Icons.location_on_outlined,
                              size: 11, color: Color(0xFFE93D95)),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(venue,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFFE93D95))),
                          ),
                        ]),
                      if (info != null && info.isNotEmpty)
                        Row(children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 11, color: Color(0xFF9E9E9E)),
                          const SizedBox(width: 3),
                          Text(info,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF9E9E9E))),
                        ]),
                    ],
                  ),
                ),
              ]),
            ),
            // Divider + action
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Divider(height: 1, color: Color(0xFFF5EEF5)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: bottom,
            ),
          ]),
        ),
      ),
    );
  }

  // ── small helpers ─────────────────────────────────────────────────────────
  Map<String, dynamic> _m(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : {};

  String _venue(Map<String, dynamic> b) {
    final v = (b['venue'] ?? '').toString().trim();
    final a = (b['area']  ?? '').toString().trim();
    return [if (v.isNotEmpty) v, if (a.isNotEmpty) a].join(', ');
  }

  Widget _avatar(Map<String, dynamic> t, double size) {
    final tag  = (t['tag']  ?? '').toString();
    final name = (t['name'] ?? '').toString();
    // gradient initials avatar
    final colors = [
      [const Color(0xFFE93D95), const Color(0xFFA64CF5)],
      [const Color(0xFF1FB5C9), const Color(0xFF0E8FA8)],
      [const Color(0xFF10B981), const Color(0xFF047857)],
      [const Color(0xFF6366F1), const Color(0xFF4338CA)],
    ];
    final idx  = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    final pair = colors[idx];
    final letters = tag.length >= 2
        ? tag.substring(0, 2).toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : '?';
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: pair),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(letters,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.36)),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: color)),
      );

  Widget _sectionLabel(String label, int count, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: color)),
          ),
        ]),
      );

  Widget _infoCard(IconData icon, String title, String msg) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: const Color(0xFFCCCCCC)),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 6),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF9E9E9E), height: 1.4)),
        ]),
      );

  Widget _centred(Widget child) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      );

  Widget _filledBtn(String label, IconData icon, VoidCallback? onTap,
      {bool small = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: small ? 36 : 44,
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 0),
        decoration: BoxDecoration(
          gradient: onTap != null
              ? const LinearGradient(
                  colors: [Color(0xFFE93D95), Color(0xFFA64CF5)])
              : null,
          color: onTap == null ? const Color(0xFFEEEEEE) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: small ? 14 : 16,
              color: onTap != null ? Colors.white : const Color(0xFF9E9E9E)),
          SizedBox(width: small ? 4 : 6),
          Text(label,
              style: TextStyle(
                  color:
                      onTap != null ? Colors.white : const Color(0xFF9E9E9E),
                  fontWeight: FontWeight.w800,
                  fontSize: small ? 12 : 13.5)),
        ]),
      ),
    );
  }

  Widget _outlineBtn(String label, IconData icon, VoidCallback? onTap,
      {Color color = const Color(0xFFE93D95)}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5)),
        ]),
      ),
    );
  }

  String _fmtWhen(dynamic iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final h    = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final min  = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour < 12 ? 'AM' : 'PM';
      return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} • $h:$min $ampm';
    } catch (_) { return ''; }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Challenge Bottom Sheet
// ════════════════════════════════════════════════════════════════════════════
class _ChallengeSheet extends StatefulWidget {
  final String teamName;

  const _ChallengeSheet({required this.teamName});

  @override
  State<_ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<_ChallengeSheet> {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  final TextEditingController _venueCtl = TextEditingController();
  final TextEditingController _areaCtl  = TextEditingController();
  DateTime?  _date;
  TimeOfDay? _time;

  @override
  void dispose() {
    _venueCtl.dispose();
    _areaCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _pink, onPrimary: Colors.white, surface: Colors.white),
        ),
        child: child!,
      ),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _pink, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  String get _dateStr {
    if (_date == null) return 'Date chunein (optional)';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${_date!.day} ${m[_date!.month - 1]} ${_date!.year}';
  }

  String get _timeStr {
    if (_time == null) return 'Time chunein (optional)';
    final h    = _time!.hour % 12 == 0 ? 12 : _time!.hour % 12;
    final min  = _time!.minute.toString().padLeft(2, '0');
    final ampm = _time!.hour < 12 ? 'AM' : 'PM';
    return '$h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 18),
        // Title
        ShaderMask(
          shaderCallback: (r) =>
              const LinearGradient(colors: [_pink, _purple]).createShader(r),
          child: Text(
            'Challenge ${widget.teamName} 🪁',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white),
          ),
        ),
        const SizedBox(height: 4),
        const Text('Match details optional hain',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E))),
        const SizedBox(height: 20),

        // Venue
        TextField(
          controller: _venueCtl,
          textCapitalization: TextCapitalization.words,
          decoration: _deco('Venue', 'Jhalana Ground, Lal Kothi…',
              Icons.location_on_outlined),
        ),
        const SizedBox(height: 10),
        // Area
        TextField(
          controller: _areaCtl,
          textCapitalization: TextCapitalization.words,
          decoration: _deco('Area / City', 'Jhalana, Jaipur', Icons.map_outlined),
        ),
        const SizedBox(height: 14),

        // Date picker
        _picker(Icons.calendar_month_rounded, _dateStr, _date != null, _pickDate),
        const SizedBox(height: 8),
        // Time picker
        _picker(Icons.access_time_rounded, _timeStr, _time != null, _pickTime),
        const SizedBox(height: 20),

        // Send button
        GestureDetector(
          onTap: () => Navigator.pop(context, {
            'venue': _venueCtl.text.trim(),
            'area':  _areaCtl.text.trim(),
            'date':  _date,
            'time':  _time,
          }),
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_pink, _purple]),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('Challenge Bhejo 🪁',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF9E9E9E))),
        ),
      ]),
    );
  }

  InputDecoration _deco(String label, String hint, IconData icon) =>
      InputDecoration(
        labelText: label, hintText: hint,
        hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC)),
        prefixIcon: Icon(icon, size: 18, color: _pink),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _pink, width: 1.5)),
        labelStyle: const TextStyle(fontSize: 13),
      );

  Widget _picker(IconData icon, String label, bool picked, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFFDE8F1) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: picked ? _pink : const Color(0xFFE0E0E0),
                width: picked ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(icon,
                size: 18,
                color: picked ? _pink : const Color(0xFFBBBBBB)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: picked
                          ? const Color(0xFF1A1A1A)
                          : const Color(0xFFBBBBBB),
                      fontWeight:
                          picked ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (picked)
              const Icon(Icons.check_circle_rounded, size: 16, color: _pink),
          ]),
        ),
      );
}


// ════════════════════════════════════════════════════════════════════════════
// Decline dialog (controller isi widget ke andar dispose hota hai)
// ════════════════════════════════════════════════════════════════════════════
class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog();

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final TextEditingController _reasonCtl = TextEditingController();

  @override
  void dispose() {
    _reasonCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Challenge decline karein?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: TextField(
        controller: _reasonCtl,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Reason (optional)',
          hintText: 'e.g. Time nahi hai abhi',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ruko',
                style: TextStyle(color: Color(0xFF9E9E9E)))),
        TextButton(
            onPressed: () => Navigator.pop(context, _reasonCtl.text.trim()),
            child: const Text('Decline karo',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w800))),
      ],
    );
  }
}
