import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'geofence_alerts';
  static const String _channelName = 'Geofence Alerts';
  static const String _channelDesc =
      'Alerts when you move outside the office area';
  static const int _breachNotificationId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(settings);

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  Future<void> showBreachNotification({
    required double distanceMeters,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Geofence breach',
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      _breachNotificationId,
      'Location Mismatch',
      'Your location is not matching the check-in area. '
          'You are ${distanceMeters.toStringAsFixed(0)}m away.',
      details,
    );
  }

  Future<void> showReturnNotification() async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      _breachNotificationId,
      'Location Matched',
      'Your location is matching the check-in area again.',
      details,
    );
  }

  Future<void> cancelBreachNotification() async {
    await _plugin.cancel(_breachNotificationId);
  }
}
