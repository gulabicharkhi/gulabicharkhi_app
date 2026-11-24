import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/search_service.dart';

/// Home search ke results (header ke neeche, home content ki jagah dikhte hain).
class SearchResults extends StatelessWidget {
  final String query;
  final bool loading;
  final String? error;
  final Map<String, dynamic>? data;
  final void Function(String teamId) onTeamTap;

  const SearchResults({
    super.key,
    required this.query,
    required this.loading,
    required this.error,
    required this.data,
    required this.onTeamTap,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.length < SearchService.minLength) {
      return _message(Icons.search_rounded, 'Kam se kam ${SearchService.minLength} letters likho');
    }
    if (error != null) {
      return _message(Icons.wifi_off_rounded, error!);
    }
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
      );
    }

    final matches = SearchService.list(data, 'matches');
    final venues = SearchService.list(data, 'venues');
    final teams = SearchService.list(data, 'teams');
    final players = SearchService.list(data, 'players');

    if (matches.isEmpty && venues.isEmpty && teams.isEmpty && players.isEmpty) {
      return _message(Icons.search_off_rounded, '"$q" ke liye kuch nahi mila');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primaryPink,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (teams.isNotEmpty) ...[
            _title('Teams'),
            for (final t in teams)
              _row(
                leading: _initial(t['tag']?.toString().isNotEmpty == true ? t['tag'] : t['name']),
                title: (t['name'] ?? '').toString(),
                subtitle: [
                  if ((t['tag'] ?? '').toString().isNotEmpty) '#${t['tag']}',
                  if ((t['region'] ?? '').toString().isNotEmpty) t['region'].toString(),
                  '${t['memberCount']}/${t['maxMembers']} players',
                ].join(' • '),
                onTap: () => onTeamTap(t['id'].toString()),
              ),
          ],
          if (matches.isNotEmpty) ...[
            _title('Matches'),
            for (final m in matches) _matchRow(m),
          ],
          if (venues.isNotEmpty) ...[
            _title('Venues'),
            for (final v in venues)
              _row(
                leading: _iconBox(Icons.stadium_outlined),
                title: (v['venue'] ?? '').toString(),
                subtitle: [
                  if ((v['area'] ?? '').toString().isNotEmpty) v['area'].toString(),
                  '${v['matches']} match${v['matches'] == 1 ? '' : 'es'}',
                ].join(' • '),
              ),
          ],
          if (players.isNotEmpty) ...[
            _title('Players'),
            for (final p in players)
              _row(
                leading: _initial(p['name']),
                title: (p['name'] ?? '').toString(),
                subtitle: [
                  if (p['team'] is Map) (p['team']['name'] ?? '').toString(),
                  if ((p['city'] ?? '').toString().isNotEmpty) p['city'].toString(),
                  '${p['matches']} matches • ${p['wins']} wins',
                ].where((e) => e.isNotEmpty).join(' • '),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------- pieces ----------------
  Widget _message(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 70, left: 30, right: 30),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 52, color: AppColors.primaryPink.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
              ),
            ],
          ),
        ),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 6),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
      );

  Widget _initial(dynamic text) {
    final s = (text ?? '').toString().trim();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        s.isEmpty ? '?' : s.substring(0, 1).toUpperCase(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }

  Widget _iconBox(IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFCE4F1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primaryPink, size: 20),
      );

  Widget _row({
    required Widget leading,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                        ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primaryPink),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _matchRow(Map<String, dynamic> m) {
    final a = (m['challengerTeam'] is Map ? m['challengerTeam']['name'] : '') ?? '';
    final b = (m['opponentTeam'] is Map ? m['opponentTeam']['name'] : '') ?? '';
    final status = (m['status'] ?? '').toString();
    final label = status == 'live'
        ? 'LIVE'
        : status == 'final'
            ? 'FINAL'
            : 'UPCOMING';
    final where = [m['venue'], m['area']]
        .map((e) => (e ?? '').toString())
        .where((e) => e.isNotEmpty)
        .join(', ');
    final score = (status == 'live' || status == 'final')
        ? '${m['challengerCuts']} - ${m['opponentCuts']}'
        : '';
    return _row(
      leading: _iconBox(Icons.gps_fixed_rounded),
      title: '$a vs $b',
      subtitle: [label, if (score.isNotEmpty) score, if (where.isNotEmpty) where].join(' • '),
    );
  }
}
