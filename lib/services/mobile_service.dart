import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'auth_service.dart';

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
}
