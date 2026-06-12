import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// The consent policy document returned by the backend
/// (`GET /api/mobile/consent/document`). The screen renders this so the policy
/// text and version are controlled server-side.
class ConsentDocument {
  final String? title;
  final String? introduction;
  final String? version;
  final List<String> sections;
  final String? fullText;
  final String? acceptanceLabel;

  const ConsentDocument({
    this.title,
    this.introduction,
    this.version,
    this.sections = const [],
    this.fullText,
    this.acceptanceLabel,
  });

  factory ConsentDocument.fromJson(Map<String, dynamic> json) {
    return ConsentDocument(
      title: json['title'] as String?,
      introduction: json['introduction'] as String?,
      version: json['version'] as String?,
      sections: (json['sections'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fullText: json['fullText'] as String?,
      acceptanceLabel: json['acceptanceLabel'] as String?,
    );
  }
}

/// Tracks the one-time user consent (requirement 27). Consent state is kept
/// locally (so a user is never re-prompted on this device) and is also reported
/// to the backend via `POST /api/mobile/consent/accept` with the accepted
/// policy version, device id and app version.
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  static const String _baseUrl = 'https://bhsmart.satoop.com';
  static const String _keyPrefix = 'consent_accepted_';
  static const String _deviceIdKey = 'device_id';

  String _key(String? username) => '$_keyPrefix${username ?? 'unknown'}';

  /// Whether this user has already accepted the consent on this device.
  Future<bool> hasConsented(String? username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(username)) ?? false;
  }

  /// Fetches the current consent policy document from the backend. Returns
  /// null on any failure so the screen can fall back to its built-in text.
  Future<ConsentDocument?> fetchDocument() async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return null;
      final resp = await http.get(
        Uri.parse('$_baseUrl/api/mobile/consent/document'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return ConsentDocument.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Fall through — caller uses the built-in fallback text.
    }
    return null;
  }

  /// Records acceptance locally and reports it to the backend with the
  /// accepted policy [version]. Returns true if the backend confirmed.
  Future<bool> submitConsent({
    required String? username,
    String? version,
  }) async {
    // Persist locally first so the form is never shown again on this device.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(username), true);

    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return false;

      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/mobile/consent/accept'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'version': version ?? '',
              'deviceId': await _getOrCreateDeviceId(),
              'appVersion': await _appVersion(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      // Network failure must not block the user — local flag already set.
      return false;
    }
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rand = Random().nextInt(1 << 30).toRadixString(36);
      id = 'flutter-$ts-$rand';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }
}
