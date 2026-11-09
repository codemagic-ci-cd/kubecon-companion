import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/reminders.dart';
import '../data/venue_time.dart';
import 'notification_service.dart';

NotificationService create() => NativeNotificationService();

class NativeNotificationService extends NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  tz.Location? _venue;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'happenings',
      'Happenings and sessions',
      channelDescription: 'Heads-up 10 minutes before meals, breaks, receptions and your saved sessions',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF0051FF),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> init() async {
    if (_ready || !_supported) return;
    try {
      tzdata.initializeTimeZones();
      _venue = tz.getLocation(venueTimeZone);
      tz.setLocalLocation(_venue!);
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  @override
  Future<NotificationPermission> permission() async {
    if (!_ready) return NotificationPermission.unsupported;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final enabled = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled();
        return enabled == true
            ? NotificationPermission.granted
            : NotificationPermission.denied;
      }
      final opts = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (opts == null) return NotificationPermission.notDetermined;
      return opts.isEnabled
          ? NotificationPermission.granted
          : NotificationPermission.notDetermined;
    } catch (_) {
      return NotificationPermission.notDetermined;
    }
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    await init();
    if (!_ready) return NotificationPermission.unsupported;
    bool? granted;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else {
        granted = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
    return granted == true
        ? NotificationPermission.granted
        : NotificationPermission.denied;
  }

  @override
  Future<void> schedule(List<Reminder> reminders) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final location = _venue ?? tz.UTC;
      for (final r in reminders) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.fireAt, location),
          notificationDetails: _details,
          // Inexact keeps us clear of the SCHEDULE_EXACT_ALARM permission;
          // a few minutes of drift is fine for "starts in 10 min".
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: r.sessionId,
        );
      }
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  @override
  Future<void> showNow(String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: 1,
        title: title,
        body: body,
        notificationDetails: _details,
      );
    } catch (e) {
      debugPrint('Show notification failed: $e');
    }
  }

  @override
  String get platformNote => _supported
      ? 'Reminders are scheduled on your device and arrive even when the app is closed.'
      : 'Notifications are not supported on this platform.';
}
