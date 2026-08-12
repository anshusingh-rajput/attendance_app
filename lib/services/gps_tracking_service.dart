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
  static const Duration _geofenceCheckInterval = Duration(seconds: 20);

  String? _deviceId;
  bool _isOutside = false;
  DateTime? _lastEventSentAt;

  /// `true` while the user is inside an allowed geofence (default true so the
  /// working-time counter runs until we positively detect a breach). The home
  /// screen listens to this to pause/resume the shift timer.
  final ValueNotifier<bool> insideGeofence = ValueNotifier<bool>(true);

  /// Short, human-readable status of the last geofence check / GPS event POST,
  /// shown on the home screen so outside-detection and event delivery are
  /// visible during testing — e.g. "event OUT • HTTP 200 • 14:33:10".
  final ValueNotifier<String> debugStatus = ValueNotifier<String>('');

  // While the user is OUTSIDE, send an event at most this often so the backend
  // keeps receiving outside points. Per requirement: outside events go every
  // 5 minutes (same cadence as the normal GPS heartbeat) — not denser.
  static const Duration _outsideHeartbeat = Duration(minutes: 5);

  String _stamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

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
      // While outside, keep feeding the backend dense outside points (the
      // transition event alone can be missed/dropped on a flaky network).
      if (_isOutside &&
          (_lastEventSentAt == null ||
              DateTime.now().difference(_lastEventSentAt!) >=
                  _outsideHeartbeat)) {
        _lastEventSentAt = DateTime.now();
        unawaited(_postEvent(pos, isInside: false));
      }
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
    final fenceCount = fences.length;
    final isInside = await GeofenceService.instance
        .isInsideAnyFence(pos.latitude, pos.longitude);
    _gpsLog(
      'checkBreach lat=${pos.latitude} lng=${pos.longitude} '
      'inside=$isInside fences=$fenceCount wasOutside=$_isOutside',
    );

    // If no fences are loaded, inside/outside cannot be judged — surface this
    // instead of silently assuming "inside" (which is what hides breaches).
    if (fenceCount == 0) {
      debugStatus.value = 'NO fences loaded — cannot detect breach • ${_stamp()}';
    }

    if (!isInside) {
      if (!_isOutside) {
        _isOutside = true;
        insideGeofence.value = false;
        // Geofence violation → send the event FIRST so that a failure in the
        // notification code below can never block the Event API call. Use the
        // reliable sender so a flaky network can't drop the violation event.
        _gpsLog('VIOLATION detected → sending event (isInside=false)');
        debugStatus.value =
            'OUTSIDE detected (fences=$fenceCount) → sending event • ${_stamp()}';
        _lastEventSentAt = DateTime.now();
        unawaited(_postEventReliable(pos, isInside: false));
        // Re-confirm the exit with fresh fixes so the Out row is reliably
        // recorded even if the first point landed on the fence edge.
        unawaited(_confirmTransition(isInside: false));
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
        debugStatus.value = 'returned INSIDE → sending event • ${_stamp()}';
        _lastEventSentAt = DateTime.now();
        unawaited(_postEventReliable(pos, isInside: true));
        // Re-confirm the return with fresh fixes so the In row is reliably
        // recorded even if the first point landed on the fence edge.
        unawaited(_confirmTransition(isInside: true));
        try {
          await NotificationService.instance.showReturnNotification();
        } catch (e) {
          _gpsLog('return notification failed: $e');
        }
      }
    }
  }

  /// After a boundary crossing, re-sends the transition a few times with fresh
  /// GPS fixes. The single transition point is often captured right on the
  /// fence edge, where GPS jitter makes the backend recompute it as the OLD
  /// state and skip it (same-state de-dup) — so the admin Event Log misses the
  /// In/Out row. Sending follow-up fixes makes at least one point land
  /// unambiguously in the new state, so the crossing is recorded.
  Future<void> _confirmTransition({
    required bool isInside,
    int attempts = 3,
    Duration gap = const Duration(seconds: 15),
  }) async {
    for (var i = 0; i < attempts; i++) {
      await Future.delayed(gap);
      if (!_isTracking) return;
      // Abort if the user has since crossed back the other way.
      if (isInside == _isOutside) return;
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
        pos = _lastPosition;
      }
      if (pos == null) continue;
      _lastEventSentAt = DateTime.now();
      await _postEvent(pos, isInside: isInside);
    }
  }

  /// Posts a transition (OUTSIDE / returned-INSIDE) event, retrying a few
  /// times on failure so a momentary network drop can't lose the event the
  /// backend needs to record the geofence violation.
  Future<void> _postEventReliable(
    Position pos, {
    required bool isInside,
    int attempts = 4,
  }) async {
    for (var i = 0; i < attempts; i++) {
      final ok = await _postEvent(pos, isInside: isInside);
      if (ok || !_isTracking) return;
      // Stop retrying a stale transition if the state flipped back meanwhile.
      if (isInside == _isOutside) return;
      await Future.delayed(Duration(seconds: 3 * (i + 1)));
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

      // Backend contract (POST /api/mobile/gps/event): all point fields are at
      // the ROOT of the body — deviceId, latitude, longitude, accuracyMeters,
      // capturedAt. (An earlier "evt" wrapper meant the backend received null
      // coordinates, so track points were never stored and the geofence
      // inside/outside duration could not be computed.) The optional
      // isInsideGeofence flag is sent as an extra hint; the backend also
      // recomputes inside/outside from the coordinates.
      final body = <String, dynamic>{
        'deviceId': deviceId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracyMeters': pos.accuracy,
        // Must match the punch-in timestamp convention: the backend stores
        // wall-clock IST with a "Z" suffix (see AttendanceService.punch ->
        // DeviceTimestamp and AttendanceDay._parseDateTime). Sending true UTC
        // here (toUtc()) made every point read as 5.5h BEFORE punch-in, so the
        // backend rejected events with "GPS point is before punch-in time."
        // (HTTP 422) — that is why violations were never recorded.
        'capturedAt': '${DateTime.now().toIso8601String()}Z',
      };
      if (isInside != null) {
        body['isInsideGeofence'] = isInside;
      }

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
      final tag = isInside == null
          ? 'event'
          : (isInside ? 'event IN' : 'event OUT');
      debugStatus.value =
          '$tag • HTTP ${response.statusCode} • ${_stamp()}';
      return ok;
    } catch (e) {
      _gpsLog('POST FAILED: $e');
      debugStatus.value = 'event POST FAILED • ${_stamp()}';
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
