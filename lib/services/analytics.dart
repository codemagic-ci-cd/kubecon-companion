import 'analytics_io.dart'
    if (dart.library.js_interop) 'analytics_web.dart'
    as impl;

/// Counts a user action in Plausible (web only; a no-op in the native apps
/// and in tests). No personal data: [props] carry only app content such as
/// a tab or room name, never search text or locations.
void track(String event, [Map<String, String> props = const {}]) {
  try {
    impl.track(event, props);
  } catch (_) {
    // Analytics must never break the app.
  }
}

/// Event names, kept in one place so the Plausible goals match.
abstract final class Events {
  static const tab = 'Tab';
  static const sessionOpen = 'Session open';
  static const save = 'Save session';
  static const reminder = 'Reminder on';
  static const calendar = 'Add to calendar';
  static const directions = 'Directions';
  static const roomSchedule = 'Room schedule';
  static const filter = 'Filter';
  static const search = 'Search';
  static const shareApp = 'Share app';
  static const shareAgenda = 'Share agenda';
  static const importAgenda = 'Import agenda';
  static const shareSpot = 'Share spot';
  static const shareSession = 'Share session';
  static const sponsorOpen = 'Sponsor open';
  static const refresh = 'Refresh';
}
