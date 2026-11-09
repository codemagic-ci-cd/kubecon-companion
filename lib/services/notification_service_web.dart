import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../data/reminders.dart';
import 'notification_service.dart';

NotificationService create() => WebNotificationService();

/// Browser notifications driven by in-app timers (fires while the PWA is
/// open). Every browser call is guarded: some browsers (iOS Safari outside
/// an installed PWA, embedded webviews) have no Notification API at all.
class WebNotificationService extends NotificationService {
  final _timers = <Timer>[];

  /// Timers further out than this are created on the next reschedule.
  static const _horizon = Duration(hours: 24);

  bool get _hasApi {
    try {
      return web.window.has('Notification');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> init() async {}

  NotificationPermission _map(String p) => switch (p) {
    'granted' => NotificationPermission.granted,
    'denied' => NotificationPermission.denied,
    _ => NotificationPermission.notDetermined,
  };

  @override
  Future<NotificationPermission> permission() async {
    if (!_hasApi) return NotificationPermission.unsupported;
    try {
      return _map(web.Notification.permission);
    } catch (_) {
      return NotificationPermission.unsupported;
    }
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    if (!_hasApi) return NotificationPermission.unsupported;
    try {
      final result = await web.Notification.requestPermission().toDart.timeout(
        const Duration(seconds: 8),
      );
      return _map(result.toDart);
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return NotificationPermission.unsupported;
    }
  }

  @override
  Future<void> schedule(List<Reminder> reminders) async {
    await cancelAll();
    final now = DateTime.now().toUtc();
    for (final r in reminders) {
      final wait = r.fireAt.difference(now);
      if (wait.isNegative || wait > _horizon) continue;
      _timers.add(
        Timer(wait, () {
          onFire?.call(r);
          showNow(r.title, r.body, tag: r.key);
        }),
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  Future<void> showNow(String title, String body, {String? tag}) async {
    if (await permission() != NotificationPermission.granted) return;
    final options = web.NotificationOptions(
      body: body,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: tag ?? 'kubecon-companion',
    );
    // Android Chrome only allows notifications through a service worker.
    try {
      final sw = web.window.navigator.serviceWorker;
      final reg = await sw.ready.toDart.timeout(const Duration(seconds: 2));
      await reg.showNotification(title, options).toDart;
      return;
    } catch (_) {
      // Fall through to the page-level constructor.
    }
    try {
      web.Notification(title, options);
    } catch (e) {
      debugPrint('Browser notification failed: $e');
    }
  }

  @override
  String get platformNote => _hasApi
      ? 'In the web app, reminders arrive while the app is open in a tab or installed to your home screen.'
      : 'This browser has no notification support. Install the app to your home screen, or keep an eye on the "Happening now" banner.';
}
