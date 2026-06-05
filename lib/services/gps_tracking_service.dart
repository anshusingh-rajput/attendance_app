import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'geofence_service.dart';
import 'notification_service.dart';

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
  bool _isTracking = false;

  String? _deviceId;
  bool _isOutside = false;
  DateTime? _lastEventSentAt;

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
            .listen(_onPosition, onError: (_) {});

    _periodicTimer =
        Timer.periodic(_periodicInterval, (_) => _sendPeriodicEvent());

    unawaited(_sendPeriodicEvent());
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;
    _isTracking = false;

    await _positionStream?.cancel();
    _positionStream = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;

    _isOutside = false;
    _lastEventSentAt = null;
    await NotificationService.instance.cancelBreachNotification();
  }

  void _onPosition(Position pos) {
    unawaited(_checkBreach(pos));
    _maybeSendThrottledEvent(pos);
  }

  void _maybeSendThrottledEvent(Position pos) {
    final now = DateTime.now();
    if (_lastEventSentAt == null ||
        now.difference(_lastEventSentAt!) >= _periodicInterval) {
      _lastEventSentAt = now;
      unawaited(_postEvent(pos));
    }
  }

  Future<void> _checkBreach(Position pos) async {
    final isInside = await GeofenceService.instance
        .isInsideAnyFence(pos.latitude, pos.longitude);

    if (!isInside) {
      if (!_isOutside) {
        _isOutside = true;
        final nearest = await GeofenceService.instance
            .nearestFenceInfo(pos.latitude, pos.longitude);
        await NotificationService.instance
            .showBreachNotification(distanceMeters: nearest?.distance ?? 0);
        unawaited(_postEvent(pos));
      }
    } else {
      if (_isOutside) {
        _isOutside = false;
        await NotificationService.instance.showReturnNotification();
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
      _lastEventSentAt = DateTime.now();
      await _postEvent(pos);
      await _checkBreach(pos);
    } catch (_) {}
  }

  Future<bool> _postEvent(Position pos) async {
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return false;

      final deviceId = _deviceId ?? await _getOrCreateDeviceId();

      final body = {
        'deviceId': deviceId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracyMeters': pos.accuracy,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
      };

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

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
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
