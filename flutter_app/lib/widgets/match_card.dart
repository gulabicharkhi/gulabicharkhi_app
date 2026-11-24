import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// Date / name formatting (no need for the intl package)
class MatchFmt {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "Sat, 12:00 PM"
  static String when(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_days[d.weekday - 1]}, $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// "5m ago"
  static String ago(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static String teamName(dynamic t) => t is Map ? (t['name'] ?? '').toString() : '';
}

class MatchStyle {
  final String label;
  final Color fg;
  final Color bg;
  final Color dot;
  const MatchStyle(this.label, this.fg, this.bg, this.dot);

  static MatchStyle of(String status) {
    switch (status) {
      case 'live':
        return const MatchStyle('LIVE', Color(0xFFB91C1C), Color(0xFFFEE2E2), Color(0xFFEF4444));
      case 'final':
        return const MatchStyle('FINAL', Color(0xFF3730A3), Color(0xFFE0E7FF), Color(0xFF6366F1));
      default: // pending / accepted
        return const MatchStyle('UPCOMING', Color(0xFFB45309), Color(0xFFFFF3CD), Color(0xFFF59E0B));
    }
  }
}

class MatchStatusPill extends StatelessWidget {
  final String status;
  const MatchStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = MatchStyle.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 3, backgroundColor: s.dot),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: TextStyle(
              fontSize: 10.5,
              color: s.fg,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for Home "Matches near you" and the Matches tab. Data: one battle from /api/battles/nearby.
class MatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final double? width;
  final VoidCallback? onTap;
  final VoidCallback? onLeaderboard;

  const MatchCard({
    super.key,
    required this.match,
    this.width,
    this.onTap,
    this.onLeaderboard,
  });

  @override
  Widget build(BuildContext context) {
    final status = (match['status'] ?? '').toString();
    final venue = (match['venue'] ?? '').toString().trim();
    final area = (match['area'] ?? '').toString().trim();
    final dist = match['distanceKm'];
    final a = MatchFmt.teamName(match['challengerTeam']);
    final b = MatchFmt.teamName(match['opponentTeam']);
    final showScore = status == 'live' || status == 'final';
    final scoreA = showScore ? '${match['challengerCuts'] ?? 0}' : '0';
    final scoreB = showScore ? '${match['opponentCuts'] ?? 0}' : '0';
    final timeLabel = status == 'live'
        ? 'Live now'
        : status == 'final'
            ? 'Ended'
            : status == 'accepted'
                ? 'Ready to start'
                : 'Awaiting accept';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                MatchStatusPill(status),
                const Spacer(),
                if (dist is num) ...[
                  const Icon(Icons.location_on_rounded, size: 14, color: AppColors.primaryPink),
                  const SizedBox(width: 2),
                  Text(
                    '$dist km',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              venue.isNotEmpty ? venue : 'Venue to be decided',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            Text(
              area.isNotEmpty ? area : 'Location not set',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textGrey),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F3F8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(child: _teamScore(a, scoreA, AppColors.primaryPink, left: true)),
                  Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Text(
                          'VS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryPurple,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text('CUTS', style: TextStyle(fontSize: 9.5, color: AppColors.textGrey)),
                    ],
                  ),
                  Expanded(child: _teamScore(b, scoreB, const Color(0xFF9B3FD9), left: false)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _action(Icons.schedule_rounded, timeLabel, const Color(0xFFD97706), null),
                _action(Icons.grid_view_rounded, 'Table', AppColors.primaryPink, onTap),
                _action(Icons.bar_chart_rounded, 'Leaderboard', AppColors.primaryPink, onLeaderboard),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamScore(String name, String score, Color dot, {required bool left}) {
    final label = Flexible(
      child: Text(
        name.isEmpty ? 'Team' : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
      ),
    );
    return Column(
      crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: left
              ? [CircleAvatar(radius: 3, backgroundColor: dot), const SizedBox(width: 5), label]
              : [label, const SizedBox(width: 5), CircleAvatar(radius: 3, backgroundColor: dot)],
        ),
        const SizedBox(height: 2),
        Text(
          score,
          style: const TextStyle(
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
