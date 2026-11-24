import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Matches (battles) + leaderboard ke GET calls.
class BattleService {
  static const _timeout = Duration(seconds: 20);

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
      return {'success': false, 'message': 'Server ne response nahi diya. Internet / backend check karo.'};
    } catch (_) {
      return {
        'success': false,
        'message': 'Server se connect nahi ho paya. Backend chal raha hai? (${AuthService.baseUrl})',
      };
    }
  }

  /// status: all | live | upcoming | final. city khaali ho to saari cities.
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

  /// Arena: incoming / outgoing challenges, active battles, challenge ke liye ready teams.
  static Future<Map<String, dynamic>> arena() => _get('/battles/arena');

  /// Challenge bhejo — venue, area, scheduledAt optional.
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

  /// Opponent captain incoming challenge reject karta hai — challenger ko notify hoga
  static Future<Map<String, dynamic>> reject(String id, {String reason = ''}) =>
      _post('/battles/${_id(id)}/reject', {
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  /// "Start battle" - dono captains dabayen to match LIVE ho jata hai.
  static Future<Map<String, dynamic>> ready(String id) => _post('/battles/${_id(id)}/ready');

  static Future<Map<String, dynamic>> claimCut(String id, {String? cutPlayerId}) =>
      _post('/battles/${_id(id)}/claim-cut', {if (cutPlayerId != null) 'cutPlayerId': cutPlayerId});

  static Future<Map<String, dynamic>> respondCut(String id, String cutId,
          {required bool approve, String reason = ''}) =>
      _post('/battles/${_id(id)}/cuts/${_id(cutId)}/respond', {
        'action': approve ? 'approve' : 'reject',
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  static Future<Map<String, dynamic>> end(String id) => _post('/battles/${_id(id)}/end');

  static Map<String, dynamic>? asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>> asList(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
}
