import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'geofence_service.dart';
import 'notification_service.dart';

void _gpsLog(String msg) {
  // Visible in `adb logcat` (filter: GPS-EVENT). Temporary diagnostics.
  developer.log(msg, name: 'GPS-EVENT');
  // ignore: avoid_print
  print('[GPS-EVENT] $msg');
}

class GpsTrackingService {
  GpsTrackingService._();
  static final GpsTrackingService instance = GpsTrackingService._();

  static const String _baseUrl = 'https://bhsmart.satoop.com';
  static const String _eventPath = '/api/mobile/gps/event';
  static const String _deviceIdKey = 'device_id';

  static const Duration _periodicInterval = Duration(minutes: 5);
  static const int _distanceFilterMeters = 10;

  StreamSubscription<Position>? _positionStream;
  Timer? _periodicTimer;
  Timer? _geofenceTimer;
  Position? _lastPosition;
  bool _isTracking = false;

  // How often to re-evaluate inside/outside the geofence, independent of
  // movement — so the working-time counter pauses promptly even if the user
  // stops moving while outside.
  static const Duration _geofenceCheckInterval = Duration(seconds: 30);

  String? _deviceId;
  bool _isOutside = false;
  DateTime? _lastEventSentAt;

  /// `true` while the user is inside an allowed geofence (default true so the
  /// working-time counter runs until we positively detect a breach). The home
  /// screen listens to this to pause/resume the shift timer.
  final ValueNotifier<bool> insideGeofence = ValueNotifier<bool>(true);

  bool get isTracking => _isTracking;

  Future<void> startTracking() async {
    if (_isTracking) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _isTracking = true;
    _isOutside = false;
    insideGeofence.value = true;
    _lastEventSentAt = null;
    _deviceId = await _getOrCreateDeviceId();
    await NotificationService.instance.init();
    unawaited(GeofenceService.instance.getFences(forceRefresh: true));

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 30),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Attendance tracking active',
        notificationText:
            'Your location is being recorded for attendance accuracy.',
        notificationIcon:
            AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen(_onPosition, onError: (e) => _gpsLog('stream error: $e'));

    _periodicTimer =
        Timer.periodic(_periodicInterval, (_) => _sendPeriodicEvent());

    // Frequent geofence re-check so the working-time counter pauses promptly
    // when outside, even when the user is not moving.
    _geofenceTimer =
        Timer.periodic(_geofenceCheckInterval, (_) => _pollGeofence());

    _gpsLog('tracking STARTED');
    unawaited(_sendPeriodicEvent());
  }

  Future<void> _pollGeofence() async {
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      _lastPosition = pos;
    } catch (_) {
      // No fresh fix this round — fall back to the last known position.
      pos = _lastPosition;
    }
    if (pos != null) {
      await _checkBreach(pos);
    }
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;

    await _positionStream?.cancel();
    _positionStream = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _geofenceTimer?.cancel();
    _geofenceTimer = null;
    _lastPosition = null;

    _isOutside = false;
    insideGeofence.value = true;
    _lastEventSentAt = null;
    await NotificationService.instance.cancelBreachNotification();
  }

  void _onPosition(Position pos) {
    _lastPosition = pos;
    unawaited(_checkBreach(pos));
    _maybeSendThrottledEvent(pos);
  }

  void _maybeSendThrottledEvent(Position pos) {
    final now = DateTime.now();
    if (_lastEventSentAt == null ||
        now.difference(_lastEventSentAt!) >= _periodicInterval) {
      _lastEventSentAt = now;
      unawaited(_postEvent(pos, isInside: !_isOutside));
    }
  }

  Future<void> _checkBreach(Position pos) async {
    final fences = await GeofenceService.instance.getFences();
    final isInside = await GeofenceService.instance
        .isInsideAnyFence(pos.latitude, pos.longitude);
    _gpsLog(
      'checkBreach lat=${pos.latitude} lng=${pos.longitude} '
      'inside=$isInside fences=${fences.length} wasOutside=$_isOutside',
    );

    if (!isInside) {
      if (!_isOutside) {
        _isOutside = true;
        insideGeofence.value = false;
        // Geofence violation → send the event FIRST so that a failure in the
        // notification code below can never block the Event API call.
        _gpsLog('VIOLATION detected → sending event (isInside=false)');
        _lastEventSentAt = DateTime.now();
        unawaited(_postEvent(pos, isInside: false));
        // Local breach notification (best-effort; must not throw upward).
        try {
          final nearest = await GeofenceService.instance
              .nearestFenceInfo(pos.latitude, pos.longitude);
          await NotificationService.instance
              .showBreachNotification(distanceMeters: nearest?.distance ?? 0);
        } catch (e) {
          _gpsLog('breach notification failed: $e');
        }
      }
    } else {
      if (_isOutside) {
        _isOutside = false;
        insideGeofence.value = true;
        // Returned inside → send the event first, then notify.
        _gpsLog('RETURN detected → sending event (isInside=true)');
        _lastEventSentAt = DateTime.now();
        unawaited(_postEvent(pos, isInside: true));
        try {
          await NotificationService.instance.showReturnNotification();
        } catch (e) {
          _gpsLog('return notification failed: $e');
        }
      }
    }
  }

  Future<void> _sendPeriodicEvent() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      // Evaluate geofence state first so the event carries the correct flag.
      await _checkBreach(pos);
      _lastEventSentAt = DateTime.now();
      await _postEvent(pos, isInside: !_isOutside);
    } catch (_) {}
  }

  Future<bool> _postEvent(Position pos, {bool? isInside}) async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return false;

      final deviceId = _deviceId ?? await _getOrCreateDeviceId();

      // Backend contract: deviceId at the root, the point itself wrapped in an
      // "evt" object. Tag each point with the geofence state so the backend can
      // record violations and compute inside/outside duration.
      final evt = <String, dynamic>{
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracyMeters': pos.accuracy,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
      };
      if (isInside != null) {
        evt['isInsideGeofence'] = isInside;
      }
      final body = <String, dynamic>{
        'deviceId': deviceId,
        'evt': evt,
      };

      _gpsLog('POST $_eventPath  body=${jsonEncode(body)}');
      final response = await http
          .post(
            Uri.parse('$_baseUrl$_eventPath'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      _gpsLog(
        'RESPONSE status=${response.statusCode} ok=$ok '
        'body=${response.body}',
      );
      return ok;
    } catch (e) {
      _gpsLog('POST FAILED: $e');
      return false;
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
