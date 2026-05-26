import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://bhsmart.satoop.com';
  static const String _tokenKey = 'auth_token';
  static const String _usernameKey = 'auth_username';

  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = _extractToken(data);
        if (token == null || token.isEmpty) {
          return LoginResult.failure('Token not found in response');
        }
        await _saveToken(token, username);
        return LoginResult.success(token);
      }

      final errorMsg = _extractError(response.body) ??
          'Login failed (${response.statusCode})';
      return LoginResult.failure(errorMsg);
    } catch (e) {
      return LoginResult.failure('Network error: ${e.toString()}');
    }
  }

  String? _extractToken(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    for (final key in ['token', 'accessToken', 'access_token', 'jwt']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final inner = data['data'];
    if (inner is Map<String, dynamic>) return _extractToken(inner);
    return null;
  }

  String? _extractError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        for (final key in ['message', 'error', 'detail']) {
          final v = data[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveToken(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_usernameKey, username);
  }

  Future<LoginResult> refreshToken() async {
    try {
      final current = await getToken();
      if (current == null || current.isEmpty) {
        return LoginResult.failure('No token to refresh');
      }
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'accessToken': current}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newToken = _extractToken(data);
        if (newToken == null || newToken.isEmpty) {
          return LoginResult.failure('Token not found in refresh response');
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, newToken);
        return LoginResult.success(newToken);
      }

      final errorMsg = _extractError(response.body) ??
          'Refresh failed (${response.statusCode})';
      return LoginResult.failure(errorMsg);
    } catch (e) {
      return LoginResult.failure('Network error: ${e.toString()}');
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
  }
}

class LoginResult {
  final bool isSuccess;
  final String? token;
  final String? error;

  const LoginResult._({required this.isSuccess, this.token, this.error});

  factory LoginResult.success(String token) =>
      LoginResult._(isSuccess: true, token: token);
  factory LoginResult.failure(String error) =>
      LoginResult._(isSuccess: false, error: error);
}
