import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// All backend calls for Teams (/api/teams/...).
/// The base URL and token come from AuthService.
class TeamService {
  static const _timeout = Duration(seconds: 60);

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      final token = await AuthService.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final uri = Uri.parse('${AuthService.baseUrl}$path');
      final payload = body == null ? null : jsonEncode(body);

      late http.Response res;
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: headers, body: payload ?? '{}').timeout(_timeout);
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: payload ?? '{}').timeout(_timeout);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers).timeout(_timeout);
          break;
        default:
          res = await http.get(uri, headers: headers).timeout(_timeout);
      }

      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
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

  // After the team changes, update the local user (the dashboard team)
  static Future<Map<String, dynamic>> _sync(Map<String, dynamic> res) async {
    if (res['success'] == true) await AuthService.refreshMe();
    return res;
  }

  static Map<String, dynamic>? asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>> asList(dynamic v) => v is List
      ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];

  // ---------------- User side ----------------
  static Future<Map<String, dynamic>> mine() => _send('GET', '/teams/mine');

  static Future<Map<String, dynamic>> create({
    required String name,
    required String tag,
    required String region,
    String about = '',
    int maxMembers = 10,
    bool isPublic = true,
  }) async =>
      _sync(await _send('POST', '/teams/create', body: {
        'name': name,
        'tag': tag,
        'region': region,
        'about': about,
        'maxMembers': maxMembers,
        'isPublic': isPublic,
      }));

  static Future<Map<String, dynamic>> browse({String q = '', int page = 1}) =>
      _send('GET', '/teams/public?page=$page&q=${Uri.encodeQueryComponent(q)}');

  static Future<Map<String, dynamic>> findByCode(String code) =>
      _send('GET', '/teams/code/${Uri.encodeComponent(code.trim())}');

  /// inviteCode => join immediately. teamId => request on a public team (or join, depending on the backend flag)
  static Future<Map<String, dynamic>> join({String? inviteCode, String? teamId}) async =>
      _sync(await _send('POST', '/teams/join', body: {
        if (inviteCode != null) 'inviteCode': inviteCode,
        if (teamId != null) 'teamId': teamId,
      }));

  static Future<Map<String, dynamic>> cancelRequest(String teamId) =>
      _send('DELETE', '/teams/requests/$teamId');

  static Future<Map<String, dynamic>> leave() async =>
      _sync(await _send('POST', '/teams/leave'));

  static Future<Map<String, dynamic>> detail(String id) => _send('GET', '/teams/$id');

  static Future<Map<String, dynamic>> matches(String id) => _send('GET', '/teams/$id/matches');

  // ---------------- Captain side ----------------
  static Future<Map<String, dynamic>> update(String id, Map<String, dynamic> fields) =>
      _send('PUT', '/teams/$id', body: fields);

  static Future<Map<String, dynamic>> regenerateCode(String id) =>
      _send('POST', '/teams/$id/regenerate-code');

  static Future<Map<String, dynamic>> requests(String id) => _send('GET', '/teams/$id/requests');

  static Future<Map<String, dynamic>> approve(String id, String userId) =>
      _send('POST', '/teams/$id/requests/$userId/approve');

  static Future<Map<String, dynamic>> reject(String id, String userId) =>
      _send('POST', '/teams/$id/requests/$userId/reject');

  static Future<Map<String, dynamic>> removeMember(String id, String userId) =>
      _send('DELETE', '/teams/$id/members/$userId');

  static Future<Map<String, dynamic>> transferCaptain(String id, String userId) =>
      _send('POST', '/teams/$id/transfer-captain', body: {'userId': userId});

  static Future<Map<String, dynamic>> disband(String id) async =>
      _sync(await _send('DELETE', '/teams/$id'));
}
