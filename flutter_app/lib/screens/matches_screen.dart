import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/battle_service.dart';
import '../widgets/match_card.dart';
import '../widgets/team_widgets.dart';
import '../widgets/leaderboard_sheet.dart';
import 'match_detail_screen.dart';
import 'battle_arena_screen.dart';

/// Bottom nav "Matches" tab
/// Live | Upcoming | Final tabs + Near me / All cities filter
class MatchesScreen extends StatefulWidget {
  final String city;
  final double bottomPadding;
  const MatchesScreen({super.key, required this.city, this.bottomPadding = 24});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _allCities = false;
  List<Map<String, dynamic>> _items = [];
  Map<String, int> _counts = {};
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  // Incoming challenges (only filled for a team captain) - Accept / Decline right here
  List<Map<String, dynamic>> _incoming = [];
  bool _incBusy = false;

  static const _statuses = ['live', 'upcoming', 'final'];
  static const _labels   = ['Live', 'Upcoming', 'Final'];
  static const _icons    = [
    Icons.sensors_rounded,
    Icons.schedule_rounded,
    Icons.flag_rounded,
  ];

  String get _city =>
      (_allCities || widget.city.trim().isEmpty) ? '' : widget.city.trim();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tab.indexIsChanging) _load();
      });
    _load();
    _loadIncoming();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() { _loading = true; _error = null; _page = 1; });
    }
    final page = more ? _page + 1 : 1;
    final res = await BattleService.nearby(
      city: _city,
      status: _statuses[_tab.index],
      page: page,
    );
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _error = (res['message'] ?? 'Could not load matches').toString();
        _loading = false;
        _loadingMore = false;
      });
      return;
    }
    final list = BattleService.asList(res['battles']);
    final counts = res['counts'];
    setState(() {
      _items    = more ? [..._items, ...list] : list;
      _page     = page;
      _hasMore  = res['hasMore'] == true;
      _loading  = false;
      _loadingMore = false;
      if (counts is Map) {
        _counts = {
          'live':     (counts['live']     as num?)?.toInt() ?? 0,
          'upcoming': (counts['upcoming'] as num?)?.toInt() ?? 0,
        };
      }
    });
  }

  Future<void> _loadIncoming() async {
    final res = await BattleService.arena();
    if (!mounted) return;
    final list = (res['success'] == true && res['isCaptain'] == true)
        ? BattleService.asList(res['incoming'])
        : <Map<String, dynamic>>[];
    setState(() => _incoming = list);
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

  Future<void> _respondIncoming(Map<String, dynamic> b, {required bool accept}) async {
    if (_incBusy) return;
    final id = b['id'].toString();
    if (!accept) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Decline the challenge?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              content: const Text('The challenger captain will be notified.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Wait')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Decline',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800))),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }
    setState(() => _incBusy = true);
    final res = accept ? await BattleService.accept(id) : await BattleService.reject(id);
    if (!mounted) return;
    setState(() => _incBusy = false);
    final ok = res['success'] == true;
    _toast((res['message'] ?? (ok ? 'Done!' : 'Something went wrong')).toString(), error: !ok);
    if (ok) {
      await _loadIncoming();
      if (mounted) _load();
    }
  }

  Widget _incomingBanner() {
    if (_incoming.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFFF3E8FF),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔔 ${_incoming.length} challenge${_incoming.length > 1 ? "s" : ""} waiting for your reply',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF6B21A8))),
          const SizedBox(height: 8),
          ..._incoming.map((b) {
            final ct = BattleService.asMap(b['challengerTeam']) ?? const {};
            final name = (ct['name'] ?? 'A team').toString();
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _open(b),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                      const Text('challenged your team',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF9E9E9E))),
                    ]),
                  ),
                ),
                OutlinedButton(
                  onPressed: _incBusy ? null : () => _respondIncoming(b, accept: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: _incBusy ? null : () => _respondIncoming(b, accept: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE93D95),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Accept ✓'),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(matchId: m['id'].toString()),
      ),
    );
    if (mounted) { _load(); _loadIncoming(); }
  }

  Future<void> _openArena() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BattleArenaScreen()),
    );
    if (mounted) { _load(); _loadIncoming(); }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        _filterRow(),
        _incomingBanner(),
        _tabBar(),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: List.generate(3, (_) => _body()),
          ),
        ),
      ],
    );
  }

  // ── header ───────────────────────────────────────────────────────────────
  Widget _header() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE93D95), Color(0xFFA64CF5)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Matches 🪁',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                Text(
                  _city.isEmpty ? 'All cities' : 'Near $_city',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          // Live count badge
          if ((_counts['live'] ?? 0) > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                      radius: 3, backgroundColor: Colors.white),
                  const SizedBox(width: 5),
                  Text('${_counts['live']} LIVE',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          // Arena button
          GestureDetector(
            onTap: _openArena,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sports_kabaddi_rounded,
                    color: Colors.white, size: 22),
              ),
              if (_incoming.isNotEmpty)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text('${_incoming.length}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── near me / all cities filter ──────────────────────────────────────────
  Widget _filterRow() {
    if (widget.city.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      color: const Color(0xFFE93D95),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _chip('Near me', !_allCities, () {
            if (_allCities) { setState(() => _allCities = false); _load(); }
          }),
          const SizedBox(width: 8),
          _chip('All cities', _allCities, () {
            if (!_allCities) { setState(() => _allCities = true); _load(); }
          }),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: on ? const Color(0xFFE93D95) : Colors.white,
          ),
        ),
      ),
    );
  }

  // ── tab bar ──────────────────────────────────────────────────────────────
  Widget _tabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tab,
        labelColor: const Color(0xFFE93D95),
        unselectedLabelColor: const Color(0xFF9E9E9E),
        indicatorColor: const Color(0xFFE93D95),
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        tabs: List.generate(3, (i) {
          final count = i == 0
              ? _counts['live']
              : i == 1
                  ? _counts['upcoming']
                  : null;
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icons[i], size: 15),
                const SizedBox(width: 5),
                Text(_labels[i]),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? const Color(0xFFEF4444)
                          : const Color(0xFFE93D95),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── body ─────────────────────────────────────────────────────────────────
  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFE93D95)));
    }
    if (_error != null) {
      return _centred(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 56, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 10),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9E9E9E))),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE93D95),
              side: const BorderSide(color: Color(0xFFE93D95)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ));
    }
    if (_items.isEmpty) {
      return _centred(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sports_score_rounded,
              size: 60, color: Color(0xFFDDBBDD)),
          const SizedBox(height: 12),
          Text(
            'No ${_labels[_tab.index].toLowerCase()} matches',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 6),
          Text(
            _city.isEmpty
                ? 'It will show up here when a captain challenges a team.'
                : 'No matches in $_city. Try "All cities".',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _openArena,
            icon: const Icon(Icons.sports_kabaddi_rounded, size: 18),
            label: const Text('Open Battle Arena'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE93D95),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ));
    }

    return RefreshIndicator(
      color: const Color(0xFFE93D95),
      onRefresh: () => _load(),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, widget.bottomPadding + 10),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _items.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextButton(
                  onPressed: _loadingMore ? null : () => _load(more: true),
                  child: _loadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE93D95)))
                      : const Text('Load more',
                          style: TextStyle(color: Color(0xFFE93D95))),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MatchCard(
              match: _items[i],
              onTap: () => _open(_items[i]),
              onLeaderboard: () => showLeaderboardSheet(context),
            ),
          );
        },
      ),
    );
  }

  Widget _centred(Widget child) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      );
}
