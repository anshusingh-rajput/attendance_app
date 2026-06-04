import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'auth_service.dart';

class LocalReferenceService {
  LocalReferenceService._();
  static final LocalReferenceService instance = LocalReferenceService._();

  Future<File> _fileFor(String username) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = username.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final folder = Directory('${dir.path}/face_refs');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File('${folder.path}/ref_$safe.jpg');
  }

  Future<File?> getCurrentUserReference() async {
    final username = await AuthService().getUsername();
    if (username == null || username.isEmpty) return null;
    final file = await _fileFor(username);
    if (await file.exists()) return file;
    return null;
  }

  Future<bool> hasCurrentUserReference() async {
    final file = await getCurrentUserReference();
    return file != null;
  }

  Future<File?> saveCurrentUserReference(File source) async {
    final username = await AuthService().getUsername();
    if (username == null || username.isEmpty) return null;
    final target = await _fileFor(username);
    return source.copy(target.path);
  }

  Future<File?> seedFromUrl(String url) async {
    try {
      final username = await AuthService().getUsername();
      if (username == null || username.isEmpty) return null;
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final target = await _fileFor(username);
      await target.writeAsBytes(response.bodyBytes);
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCurrentUserReference() async {
    final username = await AuthService().getUsername();
    if (username == null || username.isEmpty) return;
    final file = await _fileFor(username);
    if (await file.exists()) await file.delete();
  }
}
