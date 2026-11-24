import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // ✅ PRODUCTION: Live Render backend
  // Local testing ke liye: lanHost mein apna PC ka IP daalo aur _useLocal = true karo.
  static const String _liveUrl = 'https://gulabicharkhi-app.onrender.com/api';

  // --- Local dev override (sirf development ke liye) ---
  static const bool _useLocal = false;        // true karo to LAN se connect ho
  static const String lanHost = '192.168.0.150'; // apna PC ka IP yahan
  static const int lanPort = 5000;

  static String get baseUrl {
    if (_useLocal && lanHost.isNotEmpty) return 'http://$lanHost:$lanPort/api';
    return _liveUrl;
  }

  // Render free tier cold start mein 30-50 sec lag sakte hain
  static const _timeout = Duration(seconds: 60);

  // ==================== HTTP helpers ====================
  static Map<String, dynamic> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {
      'success': false,
      'message': 'Unexpected server response (${res.statusCode})',
    };
  }

  static Map<String, dynamic> _failure(Object e) {
    if (e is TimeoutException) {
      return {
        'success': false,
        'message': 'Server thoda slow hai (pehli baar open ho raha hai). Dobara try karo.',
      };
    }
    return {
      'success': false,
      'message': 'Internet connection check karo aur dobara try karo.',
    };
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (auth) {
        final token = await getToken();
        if (token != null) headers['Authorization'] = 'Bearer $token';
      }
      final res = await http
          .post(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      return _decode(res);
    } catch (e) {
      return _failure(e);
    }
  }

  static Future<Map<String, dynamic>> _get(String path, {bool auth = true}) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (auth) {
        final token = await getToken();
        if (token != null) headers['Authorization'] = 'Bearer $token';
      }
      final res =
          await http.get(Uri.parse('$baseUrl$path'), headers: headers).timeout(_timeout);
      return _decode(res);
    } catch (e) {
      return _failure(e);
    }
  }

  static Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      if (auth) {
        final token = await getToken();
        if (token != null) headers['Authorization'] = 'Bearer $token';
      }
      final res = await http
          .put(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
      return _decode(res);
    } catch (e) {
      return _failure(e);
    }
  }

  // ==================== REGISTER ====================
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String city,
  }) {
    return _post('/auth/register', {
      'email': email,
      'password': password,
      'name': name,
      'city': city,
    });
  }

  // ==================== LOGIN ====================
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final data = await _post('/auth/login', {'email': email, 'password': password});
    await _saveSession(data);
    return data;
  }

  // ==================== VERIFY OTP ====================
  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    // OTP verify ke baad session save NAHI karte - user ko pehle login karna hoga
    return _post('/auth/verify-otp', {'email': email, 'otp': otp});
  }

  // ==================== RESEND OTP ====================
  static Future<Map<String, dynamic>> resendOtp({required String email}) {
    return _post('/auth/resend-otp', {'email': email});
  }

  // ==================== FORGOT PASSWORD ====================
  // 1) email do -> OTP jayega
  static Future<Map<String, dynamic>> forgotPassword({required String email}) {
    return _post('/auth/forgot-password', {'email': email});
  }

  // 2) OTP verify -> resetToken milta hai
  static Future<Map<String, dynamic>> verifyResetOtp({
    required String email,
    required String otp,
  }) {
    return _post('/auth/verify-reset-otp', {'email': email, 'otp': otp});
  }

  // 3) naya password set karo (login nahi hota, user ko dobara login karna hoga)
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) {
    return _post('/auth/reset-password', {
      'email': email,
      'resetToken': resetToken,
      'newPassword': newPassword,
    });
  }

  // ==================== TEAMS ====================
  static Future<Map<String, dynamic>> createTeam({
    required String name,
    required bool isPublic,
  }) async {
    final data = await _post('/teams/create', {'name': name, 'isPublic': isPublic}, auth: true);
    if (data['success'] == true) await _saveTeam(data['team']);
    return data;
  }

  static Future<Map<String, dynamic>> joinTeam({String? inviteCode, String? teamId}) async {
    final data = await _post(
      '/teams/join',
      {
        if (inviteCode != null) 'inviteCode': inviteCode,
        if (teamId != null) 'teamId': teamId,
      },
      auth: true,
    );
    if (data['success'] == true) await _saveTeam(data['team']);
    return data;
  }

  static Future<List<Map<String, dynamic>>> publicTeams() async {
    final data = await _get('/teams/public');
    if (data['success'] == true && data['teams'] is List) {
      return List<Map<String, dynamic>>.from(
        (data['teams'] as List).map((t) => Map<String, dynamic>.from(t)),
      );
    }
    return [];
  }

  // Server se latest user (team wagairah) le kar local update karo
  static Future<Map<String, dynamic>?> refreshMe() async {
    final data = await _get('/auth/me');
    if (data['success'] == true && data['user'] is Map) {
      final user = Map<String, dynamic>.from(data['user']);
      await _saveUser(user);
      return user;
    }
    return null;
  }

  // ==================== PROFILE ====================
  /// Full profile data fetch karo (GET /api/profile)
  static Future<Map<String, dynamic>> getProfile() => _get('/profile');

  /// Profile update: playerName, location, phone, dateOfBirth
  static Future<Map<String, dynamic>> updateProfile({
    String? playerName,
    String? location,
    String? phone,
    String? dateOfBirth,
  }) async {
    final body = <String, dynamic>{};
    if (playerName != null) {
      body['name'] = playerName;
      body['playerName'] = playerName;
    }
    if (location != null) {
      body['city'] = location;
      body['location'] = location;
    }
    if (phone != null) body['phone'] = phone;
    if (dateOfBirth != null) body['dateOfBirth'] = dateOfBirth;

    final data = await _put('/profile', body);
    if (data['success'] == true && data['user'] is Map) {
      await _saveUser(Map<String, dynamic>.from(data['user']));
    }
    return data;
  }

  /// Profile photo update (PUT /api/profile/photo)
  static Future<Map<String, dynamic>> updatePhoto(String photoDataUri) =>
      _put('/profile/photo', {'photo': photoDataUri});

  /// Active sessions list (GET /api/profile/sessions)
  static Future<Map<String, dynamic>> getSessions() => _get('/profile/sessions');

  /// Clear all sessions (DELETE /api/profile/sessions)
  static Future<Map<String, dynamic>> clearSessions() async {
    try {
      final headers = {'Content-Type': 'application/json'};
      final token = await getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final res = await http
          .delete(Uri.parse('$baseUrl/profile/sessions'), headers: headers)
          .timeout(_timeout);
      return _decode(res);
    } catch (e) {
      return _failure(e);
    }
  }

  // ==================== LOGOUT ====================
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
  }

  // ==================== LOGIN STATUS ====================
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(userData));
    } catch (_) {
      return null;
    }
  }

  // ==================== PRIVATE HELPERS ====================
  static Future<void> _saveSession(Map<String, dynamic> data) async {
    if (data['success'] == true && data['token'] != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', data['token']);
      if (data['user'] != null) {
        await prefs.setString('user_data', jsonEncode(data['user']));
      }
    }
  }

  static Future<void> _saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(user));
  }

  static Future<void> _saveTeam(dynamic team) async {
    final user = await getCurrentUser();
    if (user == null || team == null) return;
    user['team'] = team;
    await _saveUser(user);
  }
}
