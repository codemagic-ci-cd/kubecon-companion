import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../data/official_map.dart';
import '../data/reminders.dart';
import '../data/venue_time.dart';
import '../services/notification_service.dart';

/// Everything bundled in assets/data that the first screen needs, parsed.
/// Long text (descriptions, bios) is in details.json, see [AppState.loadDetails].
class ConferenceData {
  const ConferenceData({
    required this.schedule,
    required this.venue,
    required this.happenings,
    required this.info,
    this.rawRoomNames = const {},
    this.officialMap,
  });

  final ScheduleData schedule;
  final Venue venue;
  final List<Happening> happenings;
  final ConferenceInfo info;
  final Map<String, String> rawRoomNames;

  /// The annotated official venue map; null when it could not be loaded.
  final OfficialMap? officialMap;

  List<Session> get sessions => schedule.sessions;

  static Future<ConferenceData> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    Future<Object?> read(String name) async {
      try {
        return jsonDecode(await b.loadString('assets/data/$name'));
      } catch (e) {
        debugPrint('Could not load $name: $e');
        return null;
      }
    }

    final results = await Future.wait([
      read('schedule.json'),
      read('venue.json'),
      read('happenings.json'),
      read('info.json'),
      read('rooms_raw.json'),
      read('official_map.json'),
    ]);
    OfficialMap? map;
    try {
      final m = results[5];
      if (m is Map<String, dynamic>) map = OfficialMap.fromJson(m);
    } catch (e) {
      debugPrint('Could not parse official_map.json: $e');
    }
    return ConferenceData(
      schedule: ScheduleData.fromJson(results[0]),
      venue: results[1] == null ? Venue.empty() : Venue.fromJson(results[1]),
      happenings: Happening.listFromJson(results[2]),
      info: ConferenceInfo.fromJson(results[3]),
      rawRoomNames: parseRawRoomNames(results[4]),
      officialMap: map,
    );
  }

  ResolvedLocation locate(String? roomId, {String? fallbackText}) =>
      resolveLocation(
        venue,
        roomId,
        rawNames: rawRoomNames,
        fallbackText: fallbackText,
      );

  Session? session(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Loading state of details.json.
enum DetailsStatus { loading, loaded, failed }

/// A start point the user picked for directions.
class DirectionsStart {
  const DirectionsStart({
    required this.nodeId,
    required this.label,
    required this.icon,
  });
  final String nodeId;
  final String label;
  final IconData icon;
}

/// App-wide state: data, saved sessions, settings, clock and reminders.
class AppState extends ChangeNotifier {
  AppState({
    required this.data,
    required this.prefs,
    required this.notifications,
    this.clockOffset = Duration.zero,
    DateTime Function()? clock,
    ConferenceDetails? details,
  }) : _clock = clock ?? DateTime.now,
       _details = details,
       _detailsStatus = details == null
           ? DetailsStatus.loading
           : DetailsStatus.loaded {
    _saved.addAll(prefs?.getStringList(_kSaved) ?? const []);
    _reminded.addAll(prefs?.getStringList(_kReminded) ?? const []);
    _muted.addAll(prefs?.getStringList(_kMuted) ?? const []);
    _notificationsEnabled = prefs?.getBool(_kNotify) ?? false;
    _themeMode = switch (prefs?.getString(_kTheme)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    notifications.onFire = (r) {
      _lastFired = r;
      notifyListeners();
    };
  }

  /// Start point last picked by hand on a directions screen. Kept in memory
  /// for this app session only; null means "try my location".
  DirectionsStart? directionsStart;

  static const _kSaved = 'saved_sessions';
  static const _kReminded = 'reminded_sessions';
  static const _kMuted = 'muted_sessions';
  static const _kNotify = 'notifications_enabled';
  static const _kTheme = 'theme_mode';

  final ConferenceData data;

  /// Null when browser storage is unavailable; settings then live in memory.
  final SharedPreferences? prefs;
  final NotificationService notifications;
  final Duration clockOffset;
  final DateTime Function() _clock;

  final _saved = <String>{};
  final _reminded = <String>{};

  /// Saved sessions whose (default-on) reminder the user turned off.
  final _muted = <String>{};
  bool _notificationsEnabled = false;
  ThemeMode _themeMode = ThemeMode.dark;
  NotificationPermission _permission = NotificationPermission.notDetermined;
  Reminder? _lastFired;
  ConferenceDetails? _details;
  DetailsStatus _detailsStatus;
  Future<void>? _detailsLoad;
  Timer? _ticker;
  Timer? _rescheduleDebounce;

  /// "Now" in UTC. A clock offset (web: `?now=2026-11-10T12:40`) lets you
  /// demo the app as if it were a conference day.
  DateTime get now => _clock().toUtc().add(clockOffset);

  Set<String> get saved => _saved;
  Set<String> get reminded => _reminded;
  bool get notificationsEnabled => _notificationsEnabled;
  ThemeMode get themeMode => _themeMode;
  NotificationPermission get permission => _permission;

  /// The last reminder fired by an in-app timer (web), for the banner.
  Reminder? get lastFired => _lastFired;
  void dismissFired() {
    _lastFired = null;
    notifyListeners();
  }

  ConferenceDetails? get details => _details;
  DetailsStatus get detailsStatus => _detailsStatus;

  /// [id] with description, prerequisites and speaker bios merged in once
  /// details.json has loaded; the schedule-only session before that.
  Session? detailedSession(String id) =>
      data.session(id)?.withDetails(_details);

  /// Loads details.json (descriptions, bios). Called after the first frame so
  /// it never delays the schedule; safe to call again to retry after a failure.
  Future<void> loadDetails([AssetBundle? bundle]) {
    if (_detailsStatus == DetailsStatus.loaded) return Future.value();
    return _detailsLoad ??= () async {
      if (_detailsStatus != DetailsStatus.loading) {
        _detailsStatus = DetailsStatus.loading;
        notifyListeners();
      }
      try {
        final raw = await (bundle ?? rootBundle).loadString(
          'assets/data/details.json',
          cache: false,
        );
        _details = ConferenceDetails.fromJson(jsonDecode(raw));
        _detailsStatus = DetailsStatus.loaded;
      } catch (e) {
        debugPrint('Could not load details.json: $e');
        _detailsStatus = DetailsStatus.failed;
      } finally {
        _detailsLoad = null;
      }
      notifyListeners();
    }();
  }

  Future<void> start() async {
    await notifications.init();
    _permission = await notifications.permission();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      notifyListeners();
    });
    await _reschedule();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rescheduleDebounce?.cancel();
    super.dispose();
  }

  bool isSaved(String id) => _saved.contains(id);
  bool isReminded(String id) => _reminded.contains(id);

  /// Saved sessions remind by default (unless muted); others only when the
  /// user explicitly added a reminder.
  bool isReminderOn(String id) =>
      (_saved.contains(id) && !_muted.contains(id)) || _reminded.contains(id);

  /// Saving turns its reminder on, so the first save asks for notification
  /// permission in context.
  Future<void> toggleSaved(String id) async {
    final adding = !_saved.contains(id);
    if (adding) {
      _saved.add(id);
    } else {
      _saved.remove(id);
      if (_muted.remove(id)) prefs?.setStringList(_kMuted, _muted.toList());
    }
    prefs?.setStringList(_kSaved, _saved.toList());
    notifyListeners();
    if (adding &&
        (!_notificationsEnabled ||
            _permission == NotificationPermission.notDetermined)) {
      await setNotificationsEnabled(true);
    }
    _scheduleSoon();
  }

  /// Returns true when the reminder is now on.
  Future<bool> toggleReminder(String id) async {
    if (isReminderOn(id)) {
      if (_saved.contains(id)) {
        _muted.add(id);
        prefs?.setStringList(_kMuted, _muted.toList());
      }
      if (_reminded.remove(id)) {
        prefs?.setStringList(_kReminded, _reminded.toList());
      }
      notifyListeners();
      _scheduleSoon();
      return false;
    }
    if (_saved.contains(id)) {
      _muted.remove(id);
      prefs?.setStringList(_kMuted, _muted.toList());
    } else {
      _reminded.add(id);
      prefs?.setStringList(_kReminded, _reminded.toList());
    }
    notifyListeners();
    if (!_notificationsEnabled ||
        _permission == NotificationPermission.notDetermined) {
      await setNotificationsEnabled(true);
    }
    _scheduleSoon();
    return true;
  }

  Future<NotificationPermission> setNotificationsEnabled(bool on) async {
    if (on) {
      _permission = await notifications.requestPermission();
    }
    _notificationsEnabled = on;
    await prefs?.setBool(_kNotify, on);
    await _reschedule();
    notifyListeners();
    return _permission;
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    prefs?.setString(_kTheme, mode.name);
    notifyListeners();
  }

  List<Reminder> get upcomingReminders => buildReminders(
    sessions: data.sessions,
    happenings: data.happenings,
    venue: data.venue,
    now: now,
    saved: _saved,
    reminded: _reminded,
    muted: _muted,
    rawRoomNames: data.rawRoomNames,
  );

  void _scheduleSoon() {
    _rescheduleDebounce?.cancel();
    _rescheduleDebounce = Timer(const Duration(milliseconds: 400), _reschedule);
  }

  Future<void> _reschedule() async {
    if (!_notificationsEnabled) {
      await notifications.cancelAll();
      return;
    }
    await notifications.schedule(upcomingReminders);
  }

  // ---- Derived views -----------------------------------------------------

  List<Session> sessionsOn(DateTime day) =>
      data.sessions.where((s) => sameDay(venueDay(s.start), day)).toList();

  List<Session> get savedSessions =>
      data.sessions.where((s) => _saved.contains(s.id)).toList();

  /// Happenings and highlighted/saved sessions, merged for the Now tab.
  List<TimelineItem> timelineFor(DateTime day) {
    final items = <TimelineItem>[];
    final seen = <String>{};
    for (final h in data.happenings) {
      if (!sameDay(venueDay(h.start), day) || h.isFacility) continue;
      seen.add('${h.start.toIso8601String()}|${h.kind}');
      items.add(TimelineItem.happening(h));
    }
    for (final s in data.sessions) {
      if (!sameDay(venueDay(s.start), day)) continue;
      final mine = _saved.contains(s.id) || _reminded.contains(s.id);
      if (!mine && !s.highlight) continue;
      if (!mine && s.type == 'keynote') continue; // covered by keynote block
      if (!mine && seen.contains('${s.start.toIso8601String()}|${s.type}')) {
        continue;
      }
      items.add(TimelineItem.session(s, mine: mine));
    }
    items.sort((a, b) => a.start.compareTo(b.start));
    return items;
  }

  List<Happening> facilitiesOn(DateTime day) => data.happenings
      .where((h) => h.isFacility && sameDay(venueDay(h.start), day))
      .toList();
}

/// A row in the Now tab: either a happening or a session.
class TimelineItem {
  TimelineItem.happening(Happening this.happening)
    : session = null,
      mine = false;
  TimelineItem.session(Session this.session, {this.mine = false})
    : happening = null;

  final Happening? happening;
  final Session? session;
  final bool mine;

  String get title => happening?.title ?? session!.title;
  DateTime get start => happening?.start ?? session!.start;
  DateTime get end => happening?.end ?? session!.end;
  String get kind => happening?.kind ?? session!.type;
  String? get roomId => happening?.roomId ?? session?.roomId;
  String? get locationText => happening?.location;
  String get description => happening?.description ?? session!.description;

  bool isLive(DateTime now) => !now.isBefore(start) && now.isBefore(end);
}
