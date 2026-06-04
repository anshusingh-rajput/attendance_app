import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class FaceMatchResult {
  final bool isSuccess;
  final bool matched;
  final double? similarity;
  final double? threshold;
  final String? message;
  final String? error;

  const FaceMatchResult._({
    required this.isSuccess,
    required this.matched,
    this.similarity,
    this.threshold,
    this.message,
    this.error,
  });

  factory FaceMatchResult.matched({
    required double similarity,
    required double threshold,
    String? message,
  }) =>
      FaceMatchResult._(
        isSuccess: true,
        matched: true,
        similarity: similarity,
        threshold: threshold,
        message: message,
      );

  factory FaceMatchResult.notMatched({
    required double similarity,
    required double threshold,
    String? message,
  }) =>
      FaceMatchResult._(
        isSuccess: true,
        matched: false,
        similarity: similarity,
        threshold: threshold,
        message: message,
      );

  factory FaceMatchResult.failure(String error) =>
      FaceMatchResult._(isSuccess: false, matched: false, error: error);
}

class FaceMatchService {
  FaceMatchService._();
  static final FaceMatchService instance = FaceMatchService._();

  static const String _baseUrl = 'https://face.satoop.com';
  static const String _apiKey =
      'Of7wBOh5c4j1bgsyRkay7zGZmHQbgv_4Gg2cJxp30o0';

  Future<FaceMatchResult> compareWithUrl({
    required File selfie,
    required String referenceUrl,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/face/compare');
      final request = http.MultipartRequest('POST', uri);
      request.headers['X-API-Key'] = _apiKey;
      request.headers['Accept'] = 'application/json';
      request.fields['reference_url'] = referenceUrl;
      request.files.add(
        await http.MultipartFile.fromPath('selfie', selfie.path),
      );

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      return _parseResponse(response);
    } catch (e) {
      return FaceMatchResult.failure('Face match network error: ${e.toString()}');
    }
  }

  Future<FaceMatchResult> compareWithFile({
    required File selfie,
    required File reference,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/face/compare');
      final request = http.MultipartRequest('POST', uri);
      request.headers['X-API-Key'] = _apiKey;
      request.headers['Accept'] = 'application/json';
      request.files.add(
        await http.MultipartFile.fromPath('selfie', selfie.path),
      );
      request.files.add(
        await http.MultipartFile.fromPath('reference', reference.path),
      );

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      return _parseResponse(response);
    } catch (e) {
      return FaceMatchResult.failure('Face match network error: ${e.toString()}');
    }
  }

  FaceMatchResult _parseResponse(http.Response response) {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (response.statusCode == 200 && data != null) {
      final matched = data['matched'] == true;
      final similarity = (data['similarity'] as num?)?.toDouble() ?? 0.0;
      final threshold = (data['threshold'] as num?)?.toDouble() ?? 0.70;
      final message = data['message'] as String?;
      if (matched) {
        return FaceMatchResult.matched(
          similarity: similarity,
          threshold: threshold,
          message: message,
        );
      }
      return FaceMatchResult.notMatched(
        similarity: similarity,
        threshold: threshold,
        message: message,
      );
    }

    final errorKey = data?['error'] as String?;
    final message = data?['message'] as String?;
    final reason = message ??
        _humanReadableError(errorKey) ??
        'Face match failed (${response.statusCode})';
    return FaceMatchResult.failure(reason);
  }

  String? _humanReadableError(String? errorKey) {
    switch (errorKey) {
      case 'selfie_required':
        return 'Selfie is required';
      case 'invalid_selfie':
        return 'Selfie image is invalid or too large';
      case 'reference_required':
        return 'Reference photo missing';
      case 'reference_fetch_failed':
        return 'Could not fetch reference photo';
      case 'unauthorized':
        return 'Face service authorization failed';
      case 'no_face_detected':
        return 'No face detected in selfie. Improve lighting and position';
      case 'face_service_error':
        return 'Face service temporarily unavailable. Try again.';
      default:
        return null;
    }
  }
}
