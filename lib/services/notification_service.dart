import '../data/reminders.dart';
import 'notification_service_native.dart'
    if (dart.library.js_interop) 'notification_service_web.dart'
    as impl;

/// Permission state, normalised across platforms.
enum NotificationPermission { granted, denied, notDetermined, unsupported }

/// Schedules reminders on the current platform.
///
/// Native (Android/iOS) uses flutter_local_notifications with the OS
/// scheduler, so reminders fire even when the app is closed. The web (PWA)
/// uses the browser Notification API with in-app timers, so reminders only
/// fire while a tab or the installed PWA is open; the in-app "happening now"
/// banner covers the rest.
abstract class NotificationService {
  /// Called on web when an in-app timer fires, so the UI can show a banner.
  void Function(Reminder reminder)? onFire;

  Future<void> init();
  Future<NotificationPermission> permission();
  Future<NotificationPermission> requestPermission();

  /// Replaces every scheduled reminder with [reminders].
  Future<void> schedule(List<Reminder> reminders);
  Future<void> cancelAll();
  Future<void> showNow(String title, String body);

  /// Short explanation shown in settings.
  String get platformNote;
}

NotificationService createNotificationService() => impl.create();

/// No-op implementation for tests and unsupported platforms.
class NoopNotificationService extends NotificationService {
  final scheduled = <Reminder>[];

  @override
  Future<void> init() async {}
  @override
  Future<NotificationPermission> permission() async =>
      NotificationPermission.granted;
  @override
  Future<NotificationPermission> requestPermission() async =>
      NotificationPermission.granted;
  @override
  Future<void> schedule(List<Reminder> reminders) async => scheduled
    ..clear()
    ..addAll(reminders);
  @override
  Future<void> cancelAll() async => scheduled.clear();
  @override
  Future<void> showNow(String title, String body) async {}
  @override
  String get platformNote => '';
}
