import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://bhsmart.satoop.com';
  static const String _tokenKey = 'auth_token';
  static const String _usernameKey = 'auth_username';
  static const String _profilePhotoUrlKey = 'auth_profile_photo_url';

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
        final photoUrl = _extractProfilePhotoUrl(data);
        await _saveToken(token, username, photoUrl);
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

  Future<void> _saveToken(
    String token,
    String username,
    String? profilePhotoUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_usernameKey, username);
    if (profilePhotoUrl != null && profilePhotoUrl.isNotEmpty) {
      await prefs.setString(_profilePhotoUrlKey, profilePhotoUrl);
    }
  }

  String? _extractProfilePhotoUrl(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    for (final key in ['profilePhotoUrl', 'profilePhotoURL', 'profilePhoto']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final inner = data['data'];
    if (inner is Map<String, dynamic>) return _extractProfilePhotoUrl(inner);
    return null;
  }

  Future<String?> getProfilePhotoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilePhotoUrlKey);
    return _normalizeUrl(raw);
  }

  Future<void> setProfilePhotoUrl(String url) async {
    if (url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilePhotoUrlKey, url);
  }

  String? _normalizeUrl(String? url) {
    if (url == null) return null;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '$_baseUrl$trimmed';
    }
    return '$_baseUrl/$trimmed';
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

  Future<SimpleResult> requestForgotPassword(String username) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/forgot-password'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'username': username}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SimpleResult.success();
      }
      final reason = _extractError(response.body) ??
          'Request failed (${response.statusCode})';
      return SimpleResult.failure(reason);
    } catch (e) {
      return SimpleResult.failure('Network error: ${e.toString()}');
    }
  }

  Future<SimpleResult> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/reset-password'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'token': token,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SimpleResult.success();
      }
      final reason = _extractError(response.body) ??
          'Reset failed (${response.statusCode})';
      return SimpleResult.failure(reason);
    } catch (e) {
      return SimpleResult.failure('Network error: ${e.toString()}');
    }
  }

  /// Change the password for the currently logged-in user. Sends the Bearer
  /// auth token in the header and the new password in the body — no email
  /// reset token required.
  Future<SimpleResult> changePassword({required String newPassword}) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return SimpleResult.failure('Not authenticated');
      }
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/change-password'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'newPassword': newPassword}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SimpleResult.success();
      }
      final reason = _extractError(response.body) ??
          'Change password failed (${response.statusCode})';
      return SimpleResult.failure(reason);
    } catch (e) {
      return SimpleResult.failure('Network error: ${e.toString()}');
    }
  }

  Future<void> logout() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('$_baseUrl/api/auth/logout'),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_profilePhotoUrlKey);
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

class SimpleResult {
  final bool isSuccess;
  final String? error;

  const SimpleResult._({required this.isSuccess, this.error});

  factory SimpleResult.success() => const SimpleResult._(isSuccess: true);
  factory SimpleResult.failure(String error) =>
      SimpleResult._(isSuccess: false, error: error);
}
