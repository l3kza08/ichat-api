import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ichat_channel',
    'iChat Notifications',
    description: 'Channel for iChat notifications',
    importance: Importance.max,
  );

  static const String _soundPrefKey = 'notification_sound_name';
  static String? _customSoundName;

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        // Optionally handle notification tapped payload here.
      },
    );

    if (Platform.isAndroid) {
      try {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_channel);
      } catch (_) {}
      // Request runtime notification permission (Android 13+)
      try {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      } catch (_) {}
    }

    // load custom sound setting if any
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_soundPrefKey);
      if (s != null && s.isNotEmpty) _customSoundName = s;
    } catch (_) {}

    _initialized = true;
  }

  static Future<void> showNotification(
    int id,
    String title,
    String body, {
    String? payload,
  }) async {
    await init();
    AndroidNotificationDetails androidDetails;
    DarwinNotificationDetails iosDetails;

    if (_customSoundName != null && _customSoundName!.isNotEmpty) {
      androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_customSoundName),
        icon: '@mipmap/ic_launcher',
      );
      iosDetails = DarwinNotificationDetails(sound: _customSoundName);
    } else {
      androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );
      iosDetails = const DarwinNotificationDetails();
    }

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    try {
      await _plugin.show(id, title, body, details, payload: payload);
    } catch (_) {}
  }

  /// Set a custom notification sound name. On Android this should be the
  /// filename (without extension) placed under `android/app/src/main/res/raw/`.
  /// On iOS this should be the filename including extension placed in the app bundle.
  static Future<void> setCustomSound(String? name) async {
    _customSoundName = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name == null || name.isEmpty) {
        await prefs.remove(_soundPrefKey);
      } else {
        await prefs.setString(_soundPrefKey, name);
      }
    } catch (_) {}
  }
}
