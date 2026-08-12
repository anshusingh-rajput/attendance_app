import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_day.dart';
import 'auth_service.dart';
import 'consent_service.dart';
import 'geofence_service.dart';
import 'gps_tracking_service.dart';

enum PunchDirection {
  checkIn(1),
  checkOut(2);

  final int value;
  const PunchDirection(this.value);
}

class PunchResult {
  final bool isSuccess;
  final String? error;
  final String? rawBody;

  /// True when the backend rejected the punch because a fresh privacy consent
  /// must be accepted first. The UI uses this to route the user to the consent
  /// screen instead of showing a dead-end error.
  final bool requiresConsent;

  const PunchResult._({
    required this.isSuccess,
    this.error,
    this.rawBody,
    this.requiresConsent = false,
  });

  factory PunchResult.success({String? rawBody}) =>
      PunchResult._(isSuccess: true, rawBody: rawBody);
  factory PunchResult.failure(String error, {bool requiresConsent = false}) =>
      PunchResult._(
        isSuccess: false,
        error: error,
        requiresConsent: requiresConsent,
      );
}

class DayMarkResult {
  final bool isSuccess;
  final String? error;

  const DayMarkResult._({required this.isSuccess, this.error});

  factory DayMarkResult.success() =>
      const DayMarkResult._(isSuccess: true);
  factory DayMarkResult.failure(String error) =>
      DayMarkResult._(isSuccess: false, error: error);
}

class AttendanceService {
  static const String _baseUrl = 'https://bhsmart.satoop.com';
  static const String _deviceIdKey = 'device_id';

  Future<PunchResult> punch({
    required PunchDirection direction,
    File? selfie,
    bool? faceMatchStatus,
    double? faceMatchScore,
  }) async {
    final loc = await _getLocation();
    if (loc.error != null) {
      return PunchResult.failure(loc.error!);
    }

    final pos = loc.position!;
    await GeofenceService.instance.getFences(forceRefresh: true);
    final isInside = await GeofenceService.instance
        .isInsideAnyFence(pos.latitude, pos.longitude);
    if (!isInside) {
      final nearest = await GeofenceService.instance
          .nearestFenceInfo(pos.latitude, pos.longitude);
      final detail = nearest != null
          ? '${nearest.distance.toStringAsFixed(0)}m from "${nearest.name}"'
          : 'outside allowed area';
      return PunchResult.failure(
        'You are outside the geofence ($detail). Cannot punch.',
      );
    }

    final token = await AuthService().getToken();
    if (token == null || token.isEmpty) {
      return PunchResult.failure('Not authenticated');
    }

    try {
      final deviceId = await _getOrCreateDeviceId();
      final uri = Uri.parse('$_baseUrl/api/mobile/attendance/punch');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields['Latitude'] = pos.latitude.toString();
      request.fields['Longitude'] = pos.longitude.toString();
      request.fields['Direction'] = direction.value.toString();
      request.fields['AccuracyMeters'] = pos.accuracy.toString();
      request.fields['DeviceTimestamp'] =
          '${DateTime.now().toIso8601String()}Z';
      request.fields['DeviceId'] = deviceId;

      if (faceMatchStatus != null) {
        request.fields['FaceMatchStatus'] = faceMatchStatus.toString();
      }
      if (faceMatchScore != null) {
        request.fields['FaceMatchScore'] = faceMatchScore.toString();
      }
      if (selfie != null) {
        request.files.add(
          await http.MultipartFile.fromPath('selfie', selfie.path),
        );
      }

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (direction == PunchDirection.checkIn) {
          unawaited(GpsTrackingService.instance.startTracking());
        } else {
          unawaited(GpsTrackingService.instance.stopTracking());
        }
        return PunchResult.success(rawBody: response.body);
      }
      final reason = _extractReason(response.body) ??
          'Punch failed (${response.statusCode})';
      return PunchResult.failure(
        reason,
        requiresConsent: ConsentService.isConsentError(reason),
      );
    } catch (e) {
      return PunchResult.failure('Network error: ${e.toString()}');
    }
  }

  Future<_LocationResult> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _LocationResult.error('Please enable location services');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return _LocationResult.error('Location permission denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return _LocationResult.error(
          'Location permission permanently denied. Enable from settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return _LocationResult.ok(position);
    } catch (e) {
      return _LocationResult.error('Location error: ${e.toString()}');
    }
  }

  Future<DayMarkResult> markAbsent({DateTime? date, String note = ''}) {
    return _postDayMark(
      '/api/mobile/attendance/absent',
      date: date,
      note: note,
    );
  }

  Future<DayMarkResult> markLeave({DateTime? date, String note = ''}) {
    return _postDayMark(
      '/api/mobile/attendance/leave',
      date: date,
      note: note,
    );
  }

  Future<DayMarkResult> _postDayMark(
    String path, {
    DateTime? date,
    String note = '',
  }) async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) {
        return DayMarkResult.failure('Not authenticated');
      }
      final d = date ?? DateTime.now();
      final response = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'date': _fmtDate(d),
              'note': note,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return DayMarkResult.success();
      }
      final reason = _extractReason(response.body) ??
          'Failed (${response.statusCode})';
      return DayMarkResult.failure(reason);
    } catch (e) {
      return DayMarkResult.failure('Network error: ${e.toString()}');
    }
  }

  Future<DayMarkResult> clearDayMark({DateTime? date}) async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) {
        return DayMarkResult.failure('Not authenticated');
      }
      final d = date ?? DateTime.now();
      final uri = Uri.parse('$_baseUrl/api/mobile/attendance/day-mark')
          .replace(queryParameters: {'date': _fmtDate(d)});

      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return DayMarkResult.success();
      }
      final reason = _extractReason(response.body) ??
          'Failed (${response.statusCode})';
      return DayMarkResult.failure(reason);
    } catch (e) {
      return DayMarkResult.failure('Network error: ${e.toString()}');
    }
  }

  Future<List<AttendanceDay>?> fetchSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return null;

      final uri = Uri.parse('$_baseUrl/api/mobile/attendance/summary')
          .replace(queryParameters: {
        'from': _fmtDate(from),
        'to': _fmtDate(to),
      });

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map(AttendanceDay.fromJson)
              .toList();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True if the user has checked in today but has not checked out yet.
  Future<bool> isCheckedInToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = await fetchSummary(from: today, to: today);
    if (days == null || days.isEmpty) return false;
    final rec = days.first;
    return rec.firstInAt != null && rec.lastOutAt == null;
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String? _extractReason(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        for (final key in ['reason', 'message', 'error', 'detail']) {
          final v = data[key];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return null;
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

class _LocationResult {
  final Position? position;
  final String? error;

  const _LocationResult._({this.position, this.error});

  factory _LocationResult.ok(Position p) => _LocationResult._(position: p);
  factory _LocationResult.error(String e) => _LocationResult._(error: e);
}
