import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/directions.dart';
import '../data/live_data.dart';
import '../data/models.dart';
import '../data/official_map.dart';
import '../data/reminders.dart';
import '../data/sponsors.dart';
import '../data/spot_link.dart';
import '../data/venue_time.dart';
import '../services/notification_service.dart';
import '../services/analytics.dart';

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
    this.versions = const {},
  });

  final ScheduleData schedule;
  final Venue venue;
  final List<Happening> happenings;
  final ConferenceInfo info;
  final Map<String, String> rawRoomNames;

  /// The annotated official venue map; null when it could not be loaded.
  final OfficialMap? officialMap;

  /// `fetchedAt` of the loaded schedule.json / happenings.json, when known.
  final Map<String, DateTime?> versions;

  List<Session> get sessions => schedule.sessions;

  ConferenceData copyWith({
    ScheduleData? schedule,
    List<Happening>? happenings,
    Map<String, DateTime?>? versions,
  }) => ConferenceData(
    schedule: schedule ?? this.schedule,
    venue: venue,
    happenings: happenings ?? this.happenings,
    info: info,
    rawRoomNames: rawRoomNames,
    officialMap: officialMap,
    versions: versions ?? this.versions,
  );

  /// Loads the bundled data. With [live], a newer copy saved by an earlier
  /// refresh is used for schedule.json and happenings.json (disk only, never
  /// the network).
  static Future<ConferenceData> load([
    AssetBundle? bundle,
    LiveDataSource? live,
  ]) async {
    final b = bundle ?? rootBundle;
    final schedule = loadPreferred(
      'schedule.json',
      bundled: () => b.loadString('assets/data/schedule.json'),
      parse: parseScheduleData,
      live: live,
    );
    final happenings = loadPreferred(
      'happenings.json',
      bundled: () => b.loadString('assets/data/happenings.json'),
      parse: parseHappenings,
      live: live,
    );
    Future<Object?> read(String name) async {
      try {
        return jsonDecode(await b.loadString('assets/data/$name'));
      } catch (e) {
        debugPrint('Could not load $name: $e');
        return null;
      }
    }

    final results = await Future.wait([
      read('venue.json'),
      read('info.json'),
      read('rooms_raw.json'),
      read('official_map.json'),
    ]);
    OfficialMap? map;
    try {
      final m = results[3];
      if (m is Map<String, dynamic>) map = OfficialMap.fromJson(m);
    } catch (e) {
      debugPrint('Could not parse official_map.json: $e');
    }
    final s = await schedule;
    final h = await happenings;
    if (s?.fromCache ?? false) debugPrint('Using saved schedule.json');
    return ConferenceData(
      schedule: s?.value ?? ScheduleData.fromJson(null),
      venue: results[0] == null ? Venue.empty() : Venue.fromJson(results[0]),
      happenings: h?.value ?? const [],
      info: ConferenceInfo.fromJson(results[1]),
      rawRoomNames: parseRawRoomNames(results[2]),
      officialMap: map,
      versions: {
        'schedule.json': s == null ? null : dataVersion(s.raw),
        'happenings.json': h == null ? null : dataVersion(h.raw),
      },
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

/// schedule.json; throws when it has no sessions (a broken or empty file
/// must never replace a good schedule).
ScheduleData parseScheduleData(String raw) {
  final s = ScheduleData.fromJson(jsonDecode(raw));
  if (s.sessions.isEmpty) throw const FormatException('no sessions');
  return s;
}

/// happenings.json (`{"items": [...]}` or a list).
List<Happening> parseHappenings(String raw) {
  final j = jsonDecode(raw);
  if (j is! List && !(j is Map && j['items'] is List)) {
    throw const FormatException('no items');
  }
  return Happening.listFromJson(j);
}

ConferenceDetails parseDetails(String raw) {
  final j = jsonDecode(raw);
  if (j is! Map) throw const FormatException('not an object');
  return ConferenceDetails.fromJson(j);
}

/// sponsors.json; throws when it lists none.
List<Sponsor> parseSponsors(String raw) {
  final s = Sponsor.listFromJson(jsonDecode(raw));
  if (s.isEmpty) throw const FormatException('no sponsors');
  return s;
}

/// Outcome of [AppState.refresh].
class RefreshResult {
  const RefreshResult({
    required this.updated,
    required this.failed,
    required this.at,
  });

  /// Files fetched (applied, or already current).
  final int updated;

  /// Files that could not be fetched or parsed.
  final int failed;
  final DateTime at;

  /// Nothing could be fetched: still on the saved / bundled data.
  bool get offline => updated == 0;
}

/// Loading state of details.json and sponsors.json.
enum DetailsStatus { loading, loaded, failed }

/// A request to show a venue room on the Map tab (see [AppState.showOnMap]).
/// A new object each time, so asking for the same room twice still fires.
class MapFocusRequest {
  MapFocusRequest(this.roomId);
  final String roomId;
}

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
    required this._data,
    required this.prefs,
    required this.notifications,
    this.clockOffset = Duration.zero,
    DateTime Function()? clock,
    ConferenceDetails? details,
    List<Sponsor>? sponsors,
    this.live,
    this._bundle,
  }) : _clock = clock ?? DateTime.now,
       _details = details,
       _detailsStatus = details == null
           ? DetailsStatus.loading
           : DetailsStatus.loaded,
       _sponsors = sponsors ?? const [],
       _sponsorsStatus = sponsors == null
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

  /// The loaded schedule, venue and happenings; replaced by [refresh].
  ConferenceData get data => _data;
  ConferenceData _data;

  /// Where [refresh] fetches the latest data; null disables refreshing.
  final LiveDataSource? live;
  final AssetBundle? _bundle;

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
  List<Sponsor> _sponsors;
  DetailsStatus _sponsorsStatus;
  Future<void>? _sponsorsLoad;

  /// Asks the Map tab to switch in and select a room (Expo "Show on map").
  final mapFocus = ValueNotifier<MapFocusRequest?>(null);

  void showOnMap(String roomId) => mapFocus.value = MapFocusRequest(roomId);

  /// A spot someone shared ("Share my spot" link), pinned on the Map tab
  /// until dismissed.
  final sharedSpot = ValueNotifier<SharedSpot?>(null);

  /// Bumped by [showSpot] so the shell switches to Map even when the same
  /// spot is opened again.
  final spotFocus = ValueNotifier<int>(0);

  void showSpot(SharedSpot spot) {
    sharedSpot.value = spot;
    spotFocus.value++;
  }

  void dismissSpot() => sharedSpot.value = null;

  static const _kSpotName = 'spot_name';

  /// The name last used in "Share my spot" (remembered on this device).
  String get spotName => prefs?.getString(_kSpotName) ?? _spotName;
  String _spotName = '';
  set spotName(String v) {
    _spotName = v.trim();
    prefs?.setString(_kSpotName, _spotName);
  }

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
        final b = bundle ?? _bundle ?? rootBundle;
        final r = await loadPreferred(
          'details.json',
          bundled: () => b.loadString('assets/data/details.json', cache: false),
          parse: parseDetails,
          live: live,
        );
        if (r == null) throw StateError('no details.json');
        // A refresh that finished meanwhile has newer data: keep it.
        if (_detailsStatus != DetailsStatus.loaded) {
          _details = r.value;
          _detailsStatus = DetailsStatus.loaded;
        }
      } catch (e) {
        debugPrint('Could not load details.json: $e');
        if (_detailsStatus != DetailsStatus.loaded) {
          _detailsStatus = DetailsStatus.failed;
        }
      } finally {
        _detailsLoad = null;
      }
      notifyListeners();
    }();
  }

  /// Sponsors and booths, tier then name order; empty until loaded.
  List<Sponsor> get sponsors => _sponsors;
  DetailsStatus get sponsorsStatus => _sponsorsStatus;

  /// Loads sponsors.json after the first frame, like [loadDetails]; safe to
  /// call again to retry after a failure.
  Future<void> loadSponsors([AssetBundle? bundle]) {
    if (_sponsorsStatus == DetailsStatus.loaded) return Future.value();
    return _sponsorsLoad ??= () async {
      if (_sponsorsStatus != DetailsStatus.loading) {
        _sponsorsStatus = DetailsStatus.loading;
        notifyListeners();
      }
      try {
        final b = bundle ?? _bundle ?? rootBundle;
        final r = await loadPreferred(
          'sponsors.json',
          bundled: () =>
              b.loadString('assets/data/sponsors.json', cache: false),
          parse: (raw) => Sponsor.listFromJson(jsonDecode(raw)),
          live: live,
        );
        if (r == null) throw StateError('no sponsors.json');
        if (_sponsorsStatus != DetailsStatus.loaded) {
          _sponsors = r.value;
          _sponsorsStatus = DetailsStatus.loaded;
        }
      } catch (e) {
        debugPrint('Could not load sponsors.json: $e');
        if (_sponsorsStatus != DetailsStatus.loaded) {
          _sponsorsStatus = DetailsStatus.failed;
        }
      } finally {
        _sponsorsLoad = null;
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

  // ---- Live data ---------------------------------------------------------

  Future<RefreshResult>? _refreshing;
  DateTime? _lastRefreshed;
  DateTime? _lastRefreshAttempt;

  /// Whether this platform can fetch the latest data.
  bool get canRefresh => live != null;

  /// Whether a [refresh] is running.
  bool get refreshing => _refreshing != null;

  /// When the last [refresh] got new data (app clock); null before one.
  DateTime? get lastRefreshed => _lastRefreshed;

  /// Fetches the latest schedule, details, sponsors and happenings from the
  /// live site and applies what parses. Never throws: files that fail keep
  /// the data already loaded. Concurrent calls share one fetch.
  Future<RefreshResult> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  /// [refresh] in the background when the last attempt is older than
  /// [autoRefreshAfter] (or there was none), e.g. when the app resumes.
  Future<void> autoRefresh() async {
    if (live == null || _refreshing != null) return;
    final last = _lastRefreshAttempt;
    if (last != null && _clock().difference(last) < autoRefreshAfter) return;
    await refresh();
  }

  Future<RefreshResult> _refresh() async {
    _lastRefreshAttempt = _clock();
    final src = live;
    if (src == null) {
      return RefreshResult(updated: 0, failed: liveDataFiles.length, at: now);
    }
    final bodies = await Future.wait([
      for (final name in liveDataFiles)
        () async {
          try {
            return await src.fetch(name);
          } catch (e) {
            debugPrint('Could not fetch $name: $e');
            return null;
          }
        }(),
    ]);
    var data = _data;
    final versions = {...data.versions};
    var updated = 0, failed = 0;
    for (var i = 0; i < liveDataFiles.length; i++) {
      final name = liveDataFiles[i], raw = bodies[i];
      if (raw == null) {
        failed++;
        continue;
      }
      try {
        var apply = true;
        switch (name) {
          case 'schedule.json':
            apply = fetchedIsCurrent(raw, versions[name]);
            if (apply) data = data.copyWith(schedule: parseScheduleData(raw));
          case 'happenings.json':
            apply = fetchedIsCurrent(raw, versions[name]);
            if (apply) data = data.copyWith(happenings: parseHappenings(raw));
          case 'details.json':
            _details = parseDetails(raw);
            _detailsStatus = DetailsStatus.loaded;
          case 'sponsors.json':
            _sponsors = parseSponsors(raw);
            _sponsorsStatus = DetailsStatus.loaded;
        }
        if (apply) {
          if (versions.containsKey(name)) versions[name] = dataVersion(raw);
          unawaited(_saveLive(src, name, raw));
        }
        updated++;
      } catch (e) {
        debugPrint('Could not apply $name: $e');
        failed++;
      }
    }
    final result = RefreshResult(updated: updated, failed: failed, at: now);
    if (updated > 0) {
      _data = data.copyWith(versions: versions);
      _lastRefreshed = result.at;
      notifyListeners();
      // Times or rooms may have moved: reminders follow the new data.
      await _reschedule();
    }
    return result;
  }

  /// Saves a fetched file with the fingerprint of the bundled copy, so an
  /// app update with newer bundled data wins over it later.
  Future<void> _saveLive(LiveDataSource src, String name, String raw) async {
    int? hash;
    try {
      final b = _bundle ?? rootBundle;
      hash = fingerprint(await b.loadString('assets/data/$name'));
    } catch (_) {
      hash = null;
    }
    try {
      await src.writeCache(name, raw, bundledHash: hash);
    } catch (_) {
      // Best effort.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rescheduleDebounce?.cancel();
    mapFocus.dispose();
    sharedSpot.dispose();
    spotFocus.dispose();
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
      track(Events.save);
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

  /// Sessions from [ids] that exist in the schedule and are not saved yet,
  /// in schedule order. Unknown ids are ignored.
  List<Session> importableSessions(Iterable<String> ids) {
    final wanted = ids.toSet();
    return data.sessions
        .where((s) => wanted.contains(s.id) && !_saved.contains(s.id))
        .toList();
  }

  /// Adds [ids] (e.g. from a shared agenda link) to saved. Never removes
  /// anything; unknown and already saved ids are skipped. Imported sessions
  /// get reminders like a normal save. Returns how many were added.
  Future<int> importSaved(Iterable<String> ids) async {
    final added = importableSessions(ids).map((s) => s.id).toList();
    if (added.isEmpty) return 0;
    _saved.addAll(added);
    for (final id in added) {
      _muted.remove(id);
    }
    prefs?.setStringList(_kSaved, _saved.toList());
    prefs?.setStringList(_kMuted, _muted.toList());
    notifyListeners();
    if (!_notificationsEnabled ||
        _permission == NotificationPermission.notDetermined) {
      await setNotificationsEnabled(true);
    }
    _scheduleSoon();
    return added.length;
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
    track(Events.reminder);
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

  /// Day tab to open: today, or the next conference day once everything
  /// scheduled today has ended (no point opening on a finished day).
  int get openingDayIndex {
    final i = defaultDayIndex(now);
    final day = conferenceDays[i];
    final isToday = sameDay(day, venueDay(now));
    if (!isToday || i >= conferenceDays.length - 1) return i;
    final anyLeft =
        sessionsOn(day).any((s) => s.end.isAfter(now)) ||
        timelineFor(day).any((t) => t.end.isAfter(now));
    return anyLeft ? i : i + 1;
  }

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
