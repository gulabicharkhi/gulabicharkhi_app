import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// Home search bar -> GET /api/search?q=...
class SearchService {
  static const _timeout = Duration(seconds: 60);
  static const minLength = 2;

  static Future<Map<String, dynamic>> search(String q) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      final token = await AuthService.getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final uri = Uri.parse('${AuthService.baseUrl}/search')
          .replace(queryParameters: {'q': q});
      final res = await http.get(uri, headers: headers).timeout(_timeout);

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

  static List<Map<String, dynamic>> list(Map<String, dynamic>? res, String key) {
    final v = res?[key];
    return v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }
}
