import 'package:flutter/material.dart';
import '../services/battle_service.dart';
import 'battle_arena_screen.dart';
import 'match_detail_screen.dart';

/// In-app notification list (bell icon on the dashboard).
/// A challenge notification opens the match, where the opponent captain gets Accept / Decline.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _pink = Color(0xFFE93D95);

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    final res = await BattleService.notifications();
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _error = (res['message'] ?? 'Could not load notifications').toString();
        _loading = false;
      });
      return;
    }
    setState(() {
      _items = BattleService.asList(res['notifications']);
      _loading = false;
      _error = null;
    });
  }

  Future<void> _markAllRead() async {
    final res = await BattleService.markAllNotificationsRead();
    if (!mounted) return;
    if (res['success'] == true) _load(silent: true);
  }

  Future<void> _tap(Map<String, dynamic> n) async {
    final refType = (n['refType'] ?? '').toString();
    final refId = (n['refId'] ?? '').toString();
    if (refType == 'Battle' && refId.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: refId)),
      );
      if (mounted) _load(silent: true);
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'battle_challenge': return Icons.sports_kabaddi_rounded;
      case 'battle_accepted':  return Icons.check_circle_rounded;
      case 'battle_rejected':  return Icons.cancel_rounded;
      case 'battle_cancelled': return Icons.event_busy_rounded;
      case 'battle_started':   return Icons.sensors_rounded;
      case 'battle_ended':     return Icons.flag_rounded;
      case 'cut_claimed':
      case 'cut_approved':
      case 'cut_rejected':     return Icons.content_cut_rounded;
      default:                 return Icons.notifications_rounded;
    }
  }

  String _ago(dynamic v) {
    final d = DateTime.tryParse((v ?? '').toString())?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n['read'] != true);
    return Scaffold(
      backgroundColor: const Color(0xFFFDEBF4),
      appBar: AppBar(
        backgroundColor: _pink,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          IconButton(
            tooltip: 'Battle Arena',
            icon: const Icon(Icons.sports_kabaddi_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BattleArenaScreen()),
            ),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _pink));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, size: 56, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFF9E9E9E))),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No notifications yet',
            style: TextStyle(fontSize: 15, color: Color(0xFF9E9E9E))),
      );
    }
    return RefreshIndicator(
      color: _pink,
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final n = _items[i];
          final unread = n['read'] != true;
          final type = (n['type'] ?? '').toString();
          return GestureDetector(
            onTap: () => _tap(n),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: unread ? Colors.white : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: unread ? Border.all(color: _pink.withValues(alpha: 0.35)) : null,
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon(type), color: _pink, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((n['title'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                            color: const Color(0xFF1A1A1A))),
                    const SizedBox(height: 2),
                    Text((n['body'] ?? '').toString(),
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF555555))),
                    const SizedBox(height: 4),
                    Text(_ago(n['createdAt']),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                  ]),
                ),
                if (unread)
                  Container(
                    margin: const EdgeInsets.only(top: 4, left: 6),
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(color: _pink, shape: BoxShape.circle),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
