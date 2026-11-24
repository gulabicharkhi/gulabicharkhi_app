import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/team_service.dart';
import '../screens/match_detail_screen.dart';
import 'team_widgets.dart';
import 'match_card.dart';

/// Team page > Matches tab: all battles of this team (FINAL / LIVE / UPCOMING).
class TeamMatchesTab extends StatefulWidget {
  final String teamId;
  const TeamMatchesTab({super.key, required this.teamId});

  @override
  State<TeamMatchesTab> createState() => _TeamMatchesTabState();
}

class _TeamMatchesTabState extends State<TeamMatchesTab> {
  List<Map<String, dynamic>>? _matches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _matches = null;
      _error = null;
    });
    final res = await TeamService.matches(widget.teamId);
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() => _error = (res['message'] ?? 'Could not load matches').toString());
      return;
    }
    setState(() => _matches = TeamService.asList(res['matches']));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return WhiteCard(
        child: Column(
          children: [
            EmptyState(icon: Icons.wifi_off_rounded, title: 'Could not load matches', message: _error!),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPink,
                side: const BorderSide(color: AppColors.primaryPink),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_matches == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
      );
    }
    if (_matches!.isEmpty) {
      return const WhiteCard(
        child: EmptyState(
          icon: Icons.sports_score_rounded,
          title: 'No matches yet',
          message: 'Battles this team plays will show up here.',
        ),
      );
    }
    return Column(children: [for (final m in _matches!) _row(m)]);
  }

  Widget _row(Map<String, dynamic> m) {
    final status = (m['status'] ?? '').toString();
    final opp = m['opponent'] is Map ? (m['opponent']['name'] ?? '').toString() : '';
    final venue = (m['venue'] ?? '').toString().trim();
    // Try scheduledAt first, then when, then other timestamps
    final rawWhen = m['scheduledAt'] ?? m['when'] ?? m['endedAt'] ?? m['startedAt'];
    final when = MatchFmt.when(rawWhen);
    final sub = [if (venue.isNotEmpty) venue.toUpperCase(), if (when.isNotEmpty) when].join(' • ');
    final showScore = status == 'live' || status == 'final';
    final result = m['result']?.toString();

    // Score color: W=green, L=red/pink, T=purple, no result=dark
    final Color scoreColor;
    if (result == 'W') {
      scoreColor = const Color(0xFF15803D);
    } else if (result == 'L') {
      scoreColor = AppColors.primaryPink;
    } else if (result == 'T') {
      scoreColor = const Color(0xFF8E3FD6);
    } else {
      scoreColor = AppColors.textDark;
    }

    final myCuts = m['myCuts'] ?? 0;
    final oppCuts = m['oppCuts'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: m['id'].toString())),
        ),
        child: WhiteCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: MatchStyle.of(status).bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        MatchStyle.of(status).label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: MatchStyle.of(status).fg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'vs $opp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                      ),
                  ],
                ),
              ),
              if (showScore) ...[
                const SizedBox(width: 8),
                Text(
                  '$myCuts – $oppCuts',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scoreColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
