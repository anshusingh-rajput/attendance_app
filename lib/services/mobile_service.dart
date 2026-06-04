import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'auth_service.dart';

class UpdateMeResult {
  final bool isSuccess;
  final User? user;
  final String? error;

  const UpdateMeResult._({required this.isSuccess, this.user, this.error});

  factory UpdateMeResult.success(User user) =>
      UpdateMeResult._(isSuccess: true, user: user);
  factory UpdateMeResult.failure(String error) =>
      UpdateMeResult._(isSuccess: false, error: error);
}

class MobileService {
  static const String _baseUrl = 'https://bhsmart.satoop.com';

  Future<User?> fetchMe() async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return null;

      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/mobile/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return User.fromJson(data);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<UpdateMeResult> updateMe({
    String? firstName,
    String? lastName,
    String? email,
    String? mobileNo,
    String? displayName,
    File? profilePhoto,
  }) async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) {
        return UpdateMeResult.failure('Not authenticated');
      }

      final uri = Uri.parse('$_baseUrl/api/mobile/me');
      final request = http.MultipartRequest('PATCH', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      void addField(String key, String? value) {
        if (value != null && value.isNotEmpty) {
          request.fields[key] = value;
        }
      }

      addField('FirstName', firstName);
      addField('LastName', lastName);
      addField('Email', email);
      addField('MobileNo', mobileNo);
      addField('DisplayName', displayName);

      if (profilePhoto != null) {
        request.files.add(
          await http.MultipartFile.fromPath('profilePhoto', profilePhoto.path),
        );
      }

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final user = User.fromJson(data);
          if (user.profilePhotoUrl != null &&
              user.profilePhotoUrl!.isNotEmpty) {
            await AuthService().setProfilePhotoUrl(user.profilePhotoUrl!);
          }
          return UpdateMeResult.success(user);
        }
        return UpdateMeResult.failure('Invalid response');
      }

      String? reason;
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          for (final key in ['message', 'error', 'detail', 'reason']) {
            final v = data[key];
            if (v is String && v.isNotEmpty) {
              reason = v;
              break;
            }
          }
        }
      } catch (_) {}

      return UpdateMeResult.failure(
        reason ?? 'Update failed (${response.statusCode})',
      );
    } catch (e) {
      return UpdateMeResult.failure('Network error: ${e.toString()}');
    }
  }
}
