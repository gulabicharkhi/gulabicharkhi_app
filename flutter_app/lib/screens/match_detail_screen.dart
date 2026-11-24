import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';
import '../services/battle_service.dart';
import '../widgets/leaderboard_sheet.dart';

/// Full detail screen of a match
///
/// Status flow:
///   pending  → accept / cancel buttons
///   accepted → both captains "Start Battle"
///   live     → score + "Claim Cut" + live feed (auto refresh 10s)
///   final    → result + winner banner + stats
class MatchDetailScreen extends StatefulWidget {
  final String matchId;
  const MatchDetailScreen({super.key, required this.matchId});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  Map<String, dynamic>? _m;
  String?  _error;
  bool _loading = true;
  bool _busy    = false;
  Timer? _timer;

  // Animation for LIVE pulsing dot
  late final AnimationController _pulse;
  late final Animation<double>    _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.5, end: 1.0).animate(_pulse);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      final st = _m?['status'];
      if (st == 'live' || st == 'accepted' || st == 'pending') {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await BattleService.detail(widget.matchId);
    if (!mounted) return;
    if (res['success'] != true) {
      if (silent && _m != null) return;
      setState(() {
        _error   = (res['message'] ?? 'Could not load the match').toString();
        _loading = false;
      });
      return;
    }
    setState(() {
      _m       = BattleService.asMap(res['battle']);
      _error   = null;
      _loading = false;
    });
  }

  // ── snackbar ─────────────────────────────────────────────────────────────
  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? Colors.redAccent : const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(14),
      ));
  }

  // ── action helper ─────────────────────────────────────────────────────────
  Future<void> _act(Future<Map<String, dynamic>> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await fn();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      (res['message'] ?? (res['success'] == true ? 'Done!' : 'Failed')).toString(),
      error: res['success'] != true,
    );
    if (res['success'] == true) {
      HapticFeedback.mediumImpact();
      await _load(silent: true);
    }
  }

  Future<bool> _confirm(String title, String body, String okLabel) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            content: Text(body,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF555555))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Wait',
                      style: TextStyle(color: Color(0xFF9E9E9E)))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(okLabel,
                      style: const TextStyle(
                          color: _pink, fontWeight: FontWeight.w800))),
            ],
          ),
        ) ??
        false;
  }

  // ── reject cut dialog ─────────────────────────────────────────────────────
  Future<void> _rejectCut(String cutId) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject the cut?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back',
                  style: TextStyle(color: Color(0xFF9E9E9E)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );
    final reason = ctl.text.trim();
    ctl.dispose();
    if (ok != true) return;
    await _act(() => BattleService.respondCut(
        widget.matchId, cutId,
        approve: false, reason: reason));
  }

  // ── bout sheet: who won (own team), who lost (opposing team) ──────
  Future<Map<String, List<String>>?> _openBoutSheet(Map<String, dynamic> m) {
    final myRole = (m['myCaptainRole'] ?? '').toString();
    final rosters = BattleService.asMap(m['rosters']) ?? {};
    final ch = BattleService.asMap(m['challengerTeam']) ?? {};
    final op = BattleService.asMap(m['opponentTeam']) ?? {};
    final iAmChallenger = myRole == 'challenger';
    final myPlayers  = BattleService.asList(rosters[iAmChallenger ? 'challenger' : 'opponent']);
    final oppPlayers = BattleService.asList(rosters[iAmChallenger ? 'opponent' : 'challenger']);
    final myName  = ((iAmChallenger ? ch['name'] : op['name']) ?? '').toString();
    final oppName = ((iAmChallenger ? op['name'] : ch['name']) ?? '').toString();

    return showModalBottomSheet<Map<String, List<String>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BoutSheet(
        myTeamName: myName,
        oppTeamName: oppName,
        myPlayers: myPlayers,
        oppPlayers: oppPlayers,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════
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

  // ── header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final m     = _m;
    final venue = (m?['venue'] ?? '').toString().trim();
    final area  = (m?['area']  ?? '').toString().trim();
    final title = venue.isNotEmpty ? venue : 'Match Detail';
    final sub   = area;
    final isLive = m?['status'] == 'live';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          14, MediaQuery.of(context).padding.top + 10, 14, 18),
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
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            if (sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        // LIVE pulsing badge
        if (isLive)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: _pulseAnim.value,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                      radius: 3.5, backgroundColor: Colors.white),
                  SizedBox(width: 5),
                  Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ),
        // Leaderboard
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => showLeaderboardSheet(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle),
            child: const Icon(Icons.bar_chart_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── body ──────────────────────────────────────────────────────────────────
  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _pink));
    }
    if (_m == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                size: 60, color: Color(0xFFCCCCCC)),
            const SizedBox(height: 10),
            Text(_error ?? 'Match not found',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9E9E9E))),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _pink, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    final m      = _m!;
    final status = (m['status'] ?? '').toString();
    final ch     = BattleService.asMap(m['challengerTeam']) ?? {};
    final op     = BattleService.asMap(m['opponentTeam'])   ?? {};
    final cuts   = BattleService.asList(m['cutEvents']).reversed.toList();

    return RefreshIndicator(
      color: _pink,
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
        children: [
          // ── SCOREBOARD ──────────────────────────────────────────────────
          _scoreCard(m, status, ch, op),
          const SizedBox(height: 10),

          // ── WINNER BANNER ───────────────────────────────────────────────
          if (status == 'final') ...[_winnerBanner(m, ch, op), const SizedBox(height: 10)],

          // ── CAPTAIN ACTIONS ─────────────────────────────────────────────
          _actions(m, status),

          // ── MATCH INFO ──────────────────────────────────────────────────
          const SizedBox(height: 10),
          _sectionHead('Match info'),
          _infoCard(m),
          const SizedBox(height: 10),

          // ── PLAYER BOARD (who won / lost) ───────────────────────────
          ..._playerBoard(m, status, ch, op),

          // ── CUT FEED ────────────────────────────────────────────────────
          _sectionHead('Cut feed (${cuts.length})'),
          if (cuts.isEmpty)
            _card(const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Icon(Icons.content_cut_rounded,
                    size: 40, color: Color(0xFFDDCCDD)),
                SizedBox(height: 8),
                Text('No cuts yet',
                    style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('It will appear here when a captain claims a kite cut.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFF9E9E9E))),
              ]),
            ))
          else
            _card(Column(children: [
              for (int i = 0; i < cuts.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: Color(0xFFF5EEF5)),
                _cutRow(cuts[i], ch, op, m),
              ],
            ])),
        ],
      ),
    );
  }

  // ── scoreboard ────────────────────────────────────────────────────────────
  Widget _scoreCard(Map<String, dynamic> m, String status,
      Map<String, dynamic> ch, Map<String, dynamic> op) {
    final showScore = status == 'live' || status == 'final';
    final chCuts    = showScore ? '${m['challengerCuts'] ?? 0}' : '—';
    final opCuts    = showScore ? '${m['opponentCuts']   ?? 0}' : '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Challenger side
          Expanded(child: _teamCol(ch, chCuts, Alignment.centerLeft)),
          // Centre
          SizedBox(
            width: 80,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statusPill(status),
                const SizedBox(height: 10),
                Text(showScore ? '$chCuts – $opCuts' : 'VS',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A1A))),
                const Text('CUTS',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9E9E9E))),
              ],
            ),
          ),
          // Opponent side
          Expanded(child: _teamCol(op, opCuts, Alignment.centerRight)),
        ],
      ),
    );
  }

  Widget _teamCol(Map<String, dynamic> t, String score, Alignment align) {
    final name = (t['name'] ?? '').toString();
    final tag  = (t['tag']  ?? '').toString();
    final isLeft = align == Alignment.centerLeft;
    return Column(
      crossAxisAlignment:
          isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        // avatar
        _avatar(t, 52),
        const SizedBox(height: 8),
        Text(name,
            maxLines: 2,
            textAlign: isLeft ? TextAlign.left : TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A))),
        Text(tag,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF9E9E9E))),
      ],
    );
  }

  // ── winner banner ─────────────────────────────────────────────────────────
  Widget _winnerBanner(Map<String, dynamic> m, Map<String, dynamic> ch,
      Map<String, dynamic> op) {
    final winner = m['winner']?.toString();
    final name   = winner == 'challenger'
        ? (ch['name'] ?? 'Challenger')
        : winner == 'opponent'
            ? (op['name'] ?? 'Opponent')
            : null;
    final text = name == null ? "It's a Tie! 🤝" : '$name won! 🏆';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFE93D95), Color(0xFFA64CF5)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16)),
    );
  }

  // ── captain action buttons ─────────────────────────────────────────────────
  Widget _actions(Map<String, dynamic> m, String status) {
    final role = m['myCaptainRole']?.toString();
    final id   = widget.matchId;

    if (role == null) {
      // Viewer
      final msg = status == 'live'
          ? 'The match is LIVE. Captains update the score — it refreshes automatically here.'
          : status == 'final'
              ? ''
              : 'Waiting for the captains to start.';
      if (msg.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _card(Text(msg,
            style: const TextStyle(
                fontSize: 12.5, color: Color(0xFF9E9E9E)))),
      );
    }

    final btns = <Widget>[];

    // PENDING ────────────────────────────────────────────────────────────────
    if (status == 'pending') {
      if (m['canAccept'] == true) {
        btns.add(_bigBtn(
          'Accept Challenge ✓',
          Icons.check_circle_rounded,
          () => _act(() => BattleService.accept(id)),
        ));
        btns.add(const SizedBox(height: 8));
        btns.add(_bigBtn(
          'Decline',
          Icons.close_rounded,
          () async {
            final ok = await _confirm(
                'Decline?',
                'This challenge will be cancelled.',
                'Decline');
            if (ok) await _act(() => BattleService.cancel(id));
          },
          outline: true,
          danger: true,
        ));
      } else {
        btns.add(_card(const Text(
            'Waiting for the opponent captain to accept…',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E)))));
        btns.add(const SizedBox(height: 8));
        btns.add(_bigBtn(
          'Cancel challenge',
          Icons.close_rounded,
          () async {
            final ok = await _confirm(
                'Cancel?',
                'The challenge will be withdrawn.',
                'Cancel');
            if (ok) await _act(() => BattleService.cancel(id));
          },
          outline: true,
        ));
      }
    }

    // ACCEPTED ───────────────────────────────────────────────────────────────
    else if (status == 'accepted') {
      final chReady = m['challengerReady'] == true;
      final opReady = m['opponentReady']   == true;
      final iAmReady = m['iAmReady']       == true;

      btns.add(_card(Row(children: [
        _readyDot(chReady),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_tname(m['challengerTeam'])}: ${chReady ? "Ready ✓" : "Waiting…"}',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF1A1A1A)),
          ),
        ),
        _readyDot(opReady),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_tname(m['opponentTeam'])}: ${opReady ? "Ready ✓" : "Waiting…"}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF1A1A1A)),
          ),
        ),
      ])));
      btns.add(const SizedBox(height: 8));
      btns.add(_bigBtn(
        iAmReady ? 'Waiting for the other captain…' : 'Start Battle ▶',
        Icons.play_arrow_rounded,
        iAmReady ? null : () => _act(() => BattleService.ready(id)),
      ));
      btns.add(const SizedBox(height: 8));
      btns.add(_bigBtn(
        'Cancel battle',
        Icons.close_rounded,
        () async {
          final ok =
              await _confirm('Cancel?', 'The match will be cancelled.', 'Cancel');
          if (ok) await _act(() => BattleService.cancel(id));
        },
        outline: true,
      ));
    }

    // LIVE ───────────────────────────────────────────────────────────────────
    else if (status == 'live') {
      btns.add(_bigBtn(
        'Claim Kite Cut ✂️',
        Icons.content_cut_rounded,
        () async {
          final r = await _openBoutSheet(m);
          if (r == null || !mounted) return;
          await _act(() => BattleService.claimCut(id,
              winnerIds: r['winners']!, loserIds: r['losers']!));
        },
      ));
      btns.add(const SizedBox(height: 8));
      btns.add(_bigBtn(
        'End Match 🏁',
        Icons.flag_rounded,
        () async {
          final ok = await _confirm(
              'End the match?',
              'The side with more cuts will win. This cannot be undone.',
              'End');
          if (ok) await _act(() => BattleService.end(id));
        },
        outline: true,
      ));
    }

    if (btns.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: btns),
    );
  }

  // ── info card ─────────────────────────────────────────────────────────────
  Widget _infoCard(Map<String, dynamic> m) {
    final rows = <_InfoRow>[
      _InfoRow('Venue', (m['venue'] ?? '').toString()),
      _InfoRow('Area', (m['area'] ?? '').toString()),
      _InfoRow('Challenged', _fmt(m['challengedAt'])),
      _InfoRow('Accepted', _fmt(m['acceptedAt'])),
      _InfoRow('Started', _fmt(m['startedAt'])),
      _InfoRow('Ended', _fmt(m['endedAt'])),
    ].where((r) => r.value.isNotEmpty).toList();

    if (rows.isEmpty) {
      return _card(const Text('No details yet.',
          style: TextStyle(color: Color(0xFF9E9E9E))));
    }

    return _card(Column(children: [
      for (int i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: Color(0xFFF5EEF5)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Text(rows[i].key,
                style: const TextStyle(
                    color: Color(0xFF9E9E9E), fontSize: 13)),
            const Spacer(),
            Flexible(
              child: Text(rows[i].value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF1A1A1A))),
            ),
          ]),
        ),
      ],
    ]));
  }

  // ── player board ──────────────────────────────────────────────────────────
  List<Widget> _playerBoard(Map<String, dynamic> m, String status,
      Map<String, dynamic> ch, Map<String, dynamic> op) {
    if (status != 'live' && status != 'final') return const [];
    final board = BattleService.asList(m['playerBoard']);
    if (board.isEmpty) return const [];

    Widget teamBlock(String teamKey, String teamName) {
      final rows = board.where((p) => p['team'] == teamKey).toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(teamName,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF9E9E9E))),
        ),
        for (final p in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text((p['name'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A))),
              ),
              Text('${p['wins'] ?? 0}W',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15803D))),
              const SizedBox(width: 10),
              Text('${p['losses'] ?? 0}L',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB91C1C))),
            ]),
          ),
      ]);
    }

    return [
      _sectionHead('Players'),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        teamBlock('challenger', _tname(ch)),
        teamBlock('opponent', _tname(op)),
      ])),
      const SizedBox(height: 4),
    ];
  }

  // ── cut row ───────────────────────────────────────────────────────────────
  Widget _cutRow(Map<String, dynamic> c, Map<String, dynamic> ch,
      Map<String, dynamic> op, Map<String, dynamic> m) {
    final byCh  = c['claimedByTeam'].toString() == (ch['id'] ?? '').toString();
    final team  = byCh ? _tname(ch) : _tname(op);
    final st    = (c['status'] ?? '').toString();
    final reason = (c['rejectionReason'] ?? '').toString();
    final claimer = c['claimedBy'] is Map
        ? (c['claimedBy']['name'] ?? '').toString()
        : '';
    String namesOf(dynamic v) => BattleService.asList(v)
        .map((e) => (e['name'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .join(' + ');
    final winnersText = namesOf(c['winners']);
    final losersText  = namesOf(c['losers']);

    final col = st == 'approved'
        ? const Color(0xFF15803D)
        : st == 'rejected'
            ? const Color(0xFFB91C1C)
            : const Color(0xFFB45309);
    final bg = st == 'approved'
        ? const Color(0xFFDCFCE7)
        : st == 'rejected'
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFFF3CD);

    // Can I respond to this cut?
    final myRole = m['myCaptainRole']?.toString();
    final canRespond = m['status'] == 'live' &&
        st == 'pending' &&
        myRole != null &&
        ((myRole == 'challenger' && !byCh) ||
            (myRole == 'opponent' && byCh));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.content_cut_rounded, size: 18, color: col),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  winnersText.isNotEmpty && losersText.isNotEmpty
                      ? '$winnersText defeated $losersText'
                      : '$team claimed a cut',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A))),
              Text(
                [
                  team,
                  if (claimer.isNotEmpty) 'by $claimer',
                  _ago(c['createdAt']),
                  if (st == 'rejected' && reason.isNotEmpty) 'Reason: $reason',
                ].where((e) => e.isNotEmpty).join(' • '),
                style: const TextStyle(
                    fontSize: 11.5, color: Color(0xFF9E9E9E)),
              ),
            ]),
          ),
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(10)),
            child: Text(
              st.isEmpty
                  ? ''
                  : st[0].toUpperCase() + st.substring(1),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: col),
            ),
          ),
        ]),
        // Approve / Reject buttons
        if (canRespond) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _smallBtn('Reject', Colors.redAccent, false,
                _busy
                    ? null
                    : () => _rejectCut((c['id'] ?? '').toString())),
            const SizedBox(width: 8),
            _smallBtn('Approve ✓', const Color(0xFF15803D), true,
                _busy
                    ? null
                    : () => _act(() => BattleService.respondCut(
                          widget.matchId,
                          (c['id'] ?? '').toString(),
                          approve: true,
                        ))),
          ]),
        ],
      ]),
    );
  }

  // ── small helpers ─────────────────────────────────────────────────────────
  Widget _sectionHead(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A))),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
        child: child,
      );

  Widget _statusPill(String status) {
    final label = status == 'live'
        ? 'LIVE'
        : status == 'final'
            ? 'FINAL'
            : status == 'accepted'
                ? 'ACCEPTED'
                : status == 'cancelled'
                    ? 'CANCELLED'
                    : 'PENDING';
    final color = status == 'live'
        ? const Color(0xFFEF4444)
        : status == 'final'
            ? const Color(0xFF6366F1)
            : status == 'accepted'
                ? const Color(0xFF15803D)
                : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 3, backgroundColor: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: color)),
      ]),
    );
  }

  Widget _avatar(Map<String, dynamic> t, double size) {
    final name = (t['name'] ?? '').toString();
    final tag  = (t['tag']  ?? '').toString();
    final letters = tag.length >= 2
        ? tag.substring(0, 2).toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : '?';
    final idx  = name.isNotEmpty ? name.codeUnitAt(0) % 4 : 0;
    final cols = [
      [const Color(0xFFE93D95), const Color(0xFFA64CF5)],
      [const Color(0xFF6366F1), const Color(0xFF4338CA)],
      [const Color(0xFF10B981), const Color(0xFF047857)],
      [const Color(0xFFF59E0B), const Color(0xFFD97706)],
    ][idx];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: cols),
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

  Widget _readyDot(bool ready) => CircleAvatar(
        radius: 5,
        backgroundColor:
            ready ? const Color(0xFF15803D) : const Color(0xFFB45309),
      );

  Widget _bigBtn(String label, IconData icon, VoidCallback? onTap,
      {bool outline = false, bool danger = false}) {
    final color =
        danger ? Colors.redAccent : _pink;
    if (outline) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.5),
          minimumSize: const Size(double.infinity, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: onTap != null
            ? const LinearGradient(
                colors: [Color(0xFFE93D95), Color(0xFFA64CF5)])
            : null,
        color: onTap == null ? const Color(0xFFEEEEEE) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor:
              onTap != null ? Colors.white : const Color(0xFF9E9E9E),
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _smallBtn(String label, Color color, bool filled,
      VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                color: filled ? Colors.white : color,
                fontWeight: FontWeight.w800,
                fontSize: 12.5)),
      ),
    );
  }

  String _tname(dynamic t) =>
      t is Map ? (t['name'] ?? '').toString() : '';

  String _fmt(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (d == null) return '';
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h    = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min  = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} • $h:$min $ampm';
  }

  String _ago(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _InfoRow {
  final String key;
  final String value;
  const _InfoRow(this.key, this.value);
}


// ════════════════════════════════════════════════════════════════════════════
// Bout sheet — the captain picks who won (own team) and who lost (opposing team)
// ════════════════════════════════════════════════════════════════════════════
class _BoutSheet extends StatefulWidget {
  final String myTeamName;
  final String oppTeamName;
  final List<Map<String, dynamic>> myPlayers;
  final List<Map<String, dynamic>> oppPlayers;

  const _BoutSheet({
    required this.myTeamName,
    required this.oppTeamName,
    required this.myPlayers,
    required this.oppPlayers,
  });

  @override
  State<_BoutSheet> createState() => _BoutSheetState();
}

class _BoutSheetState extends State<_BoutSheet> {
  static const _pink   = Color(0xFFE93D95);
  static const _purple = Color(0xFFA64CF5);

  final Set<String> _winners = {};
  final Set<String> _losers  = {};

  bool get _canSubmit => _winners.isNotEmpty && _losers.isNotEmpty;

  Widget _group(String title, String sub, List<Map<String, dynamic>> players,
      Set<String> selected, Color accent) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A1A))),
      const SizedBox(height: 2),
      Text(sub,
          style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
      const SizedBox(height: 8),
      if (players.isEmpty)
        const Text('No players found in this team.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E)))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in players)
            FilterChip(
              label: Text((p['name'] ?? '').toString()),
              selected: selected.contains(p['id'].toString()),
              selectedColor: accent.withValues(alpha: 0.18),
              checkmarkColor: accent,
              labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected.contains(p['id'].toString())
                      ? accent
                      : const Color(0xFF444444)),
              onSelected: (v) => setState(() {
                final id = p['id'].toString();
                v ? selected.add(id) : selected.remove(id);
              }),
            ),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFDDDDDD),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Kite Cut Claim ✂️',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 4),
              const Text(
                  'Pick who won and who lost. You can pick more than one player.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E))),
              const SizedBox(height: 16),
              _group('${widget.myTeamName} — winners',
                  'Player(s) of our team who made the cut',
                  widget.myPlayers, _winners, const Color(0xFF15803D)),
              const SizedBox(height: 16),
              _group('${widget.oppTeamName} — losers',
                  'Player(s) of the opposing team whose kite was cut',
                  widget.oppPlayers, _losers, const Color(0xFFB91C1C)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _canSubmit
                    ? () => Navigator.pop(context, {
                          'winners': _winners.toList(),
                          'losers': _losers.toList(),
                        })
                    : null,
                child: Container(
                  width: double.infinity, height: 52,
                  decoration: BoxDecoration(
                    gradient: _canSubmit
                        ? const LinearGradient(colors: [_pink, _purple])
                        : null,
                    color: _canSubmit ? null : const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text('Send claim',
                      style: TextStyle(
                          color: _canSubmit
                              ? Colors.white
                              : const Color(0xFF9E9E9E),
                          fontWeight: FontWeight.w900,
                          fontSize: 15)),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF9E9E9E))),
                ),
              ),
            ]),
      ),
    );
  }
}
