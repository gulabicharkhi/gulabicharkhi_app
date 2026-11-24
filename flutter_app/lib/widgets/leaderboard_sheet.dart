import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../services/battle_service.dart';
import 'team_widgets.dart';

/// Opens from the match card "Leaderboard": top teams (wins, then cuts).
Future<void> showLeaderboardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LeaderboardSheet(),
  );
}

class LeaderboardSheet extends StatefulWidget {
  const LeaderboardSheet({super.key});

  @override
  State<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<LeaderboardSheet> {
  List<Map<String, dynamic>>? _teams;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _teams = null;
      _error = null;
    });
    final res = await BattleService.leaderboard();
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() => _error = (res['message'] ?? 'Could not load the leaderboard').toString());
      return;
    }
    setState(() => _teams = BattleService.asList(res['teams']));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Leaderboard',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textDark),
              ),
              const Text(
                'More wins; if tied, more cuts',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
              const SizedBox(height: 10),
              Flexible(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textGrey)),
            const SizedBox(height: 10),
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
    if (_teams == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50),
        child: Center(child: CircularProgressIndicator(color: AppColors.primaryPink)),
      );
    }
    if (_teams!.isEmpty) {
      return const EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No ranked teams yet',
        message: 'Teams will show up here as soon as the first match ends.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _teams!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _row(_teams![i]),
    );
  }

  Widget _row(Map<String, dynamic> t) {
    final rank = (t['rank'] as num?)?.toInt() ?? 0;
    final mine = t['isMine'] == true;
    final medal = rank == 1
        ? const Color(0xFFF59E0B)
        : rank == 2
            ? const Color(0xFF9CA3AF)
            : rank == 3
                ? const Color(0xFFB45309)
                : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFFCE4F1) : const Color(0xFFF8F3F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: medal != null
                ? Icon(Icons.emoji_events_rounded, color: medal, size: 22)
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textGrey),
                  ),
          ),
          const SizedBox(width: 8),
          TeamAvatar(name: (t['name'] ?? '').toString(), tag: (t['tag'] ?? '').toString(), size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (t['name'] ?? '').toString() + (mine ? '  (You)' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '${t['wins']}W  ${t['losses']}L  ${t['ties']}T  •  ${t['cutsScored']} cuts',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '${t['wins']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryPink,
                ),
              ),
              const Text('wins', style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
            ],
          ),
        ],
      ),
    );
  }
}
