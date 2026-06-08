import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications so the owner is actively told what the background
/// reminder system did — instead of silent success/failure buried in history.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'reminder_status';
  static const _channelName = 'Reminder status';

  static bool _ready = false;

  /// Safe to call from both the UI and the background isolate.
  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Updates about automatic reminder messages',
          importance: Importance.high,
        ));
    _ready = true;
  }

  static Future<void> show(String title, String body, {int id = 1001}) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
    );
  }
}
