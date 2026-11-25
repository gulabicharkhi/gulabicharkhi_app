import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// GET calls for Matches (battles) + leaderboard.
class BattleService {
  static const _timeout = Duration(seconds: 60);

  static Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) =>
      _request('GET', path, query: query);

  static Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) =>
      _request('POST', path, body: body ?? const {});

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      final token = await AuthService.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final uri = Uri.parse('${AuthService.baseUrl}$path').replace(queryParameters: query);
      final res = method == 'POST'
          ? await http.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(_timeout)
          : await http.get(uri, headers: headers).timeout(_timeout);
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'success': false, 'message': 'Unexpected server response (${res.statusCode})'};
    } on TimeoutException {
      return {'success': false, 'message': 'The server did not respond. Check the internet / backend.'};
    } catch (_) {
      return {
        'success': false,
        'message': 'Could not connect to the server. Is the backend running? (${AuthService.baseUrl})',
      };
    }
  }

  /// status: all | live | upcoming | final. If city is empty, all cities.
  static Future<Map<String, dynamic>> nearby({
    String city = '',
    String status = 'all',
    String q = '',
    int page = 1,
    int limit = 20,
  }) =>
      _get('/battles/nearby', {
        if (city.trim().isNotEmpty) 'city': city.trim(),
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'status': status,
        'page': '$page',
        'limit': '$limit',
      });

  static Future<Map<String, dynamic>> detail(String id) =>
      _get('/battles/${Uri.encodeComponent(id)}');

  static Future<Map<String, dynamic>> leaderboard() => _get('/teams/leaderboard');

  // ==================== Battle flow (captain actions) ====================

  /// Arena: incoming / outgoing challenges, active battles, teams ready to be challenged.
  static Future<Map<String, dynamic>> arena() => _get('/battles/arena');

  /// Send a challenge — venue, area, scheduledAt optional.
  static Future<Map<String, dynamic>> challenge({
    required String opponentTeamId,
    String venue = '',
    String area = '',
    DateTime? scheduledAt,
  }) =>
      _post('/battles/challenge', {
        'opponentTeamId': opponentTeamId,
        if (venue.trim().isNotEmpty) 'venue': venue.trim(),
        if (area.trim().isNotEmpty) 'area': area.trim(),
        if (scheduledAt != null) 'scheduledAt': scheduledAt.toIso8601String(),
      });

  static String _id(String id) => Uri.encodeComponent(id);

  static Future<Map<String, dynamic>> accept(String id) => _post('/battles/${_id(id)}/accept');
  static Future<Map<String, dynamic>> cancel(String id) => _post('/battles/${_id(id)}/cancel');

  /// The opponent captain rejects an incoming challenge — the challenger will be notified
  static Future<Map<String, dynamic>> reject(String id, {String reason = ''}) =>
      _post('/battles/${_id(id)}/reject', {
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  /// "Start battle" - when both captains press it, the match goes LIVE.
  static Future<Map<String, dynamic>> ready(String id) => _post('/battles/${_id(id)}/ready');

  /// Cut / bout claim: winnerIds = players of our team who won, loserIds = players of the opposing team who lost.
  static Future<Map<String, dynamic>> claimCut(String id,
          {required List<String> winnerIds, required List<String> loserIds}) =>
      _post('/battles/${_id(id)}/claim-cut', {
        'winnerPlayerIds': winnerIds,
        'loserPlayerIds': loserIds,
      });

  static Future<Map<String, dynamic>> respondCut(String id, String cutId,
          {required bool approve, String reason = ''}) =>
      _post('/battles/${_id(id)}/cuts/${_id(cutId)}/respond', {
        'action': approve ? 'approve' : 'reject',
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  static Future<Map<String, dynamic>> end(String id) => _post('/battles/${_id(id)}/end');

  // ==================== Notifications (in-app list) ====================
  static Future<Map<String, dynamic>> notifications({int limit = 50}) =>
      _get('/notifications', {'limit': '$limit'});

  static Future<Map<String, dynamic>> unreadNotifications() =>
      _get('/notifications', {'limit': '1', 'unreadOnly': 'true'});

  static Future<Map<String, dynamic>> markAllNotificationsRead() =>
      _post('/notifications/read-all');

  static Map<String, dynamic>? asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>> asList(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
}
