import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/live_data.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/sponsors.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/expo_screen.dart';
import 'package:kubecon_companion/screens/home_shell.dart';
import 'package:kubecon_companion/screens/now_screen.dart';
import 'package:kubecon_companion/screens/saved_screen.dart';
import 'package:kubecon_companion/screens/schedule_screen.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/live_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Serves data files from memory; null bodies fail like a network error.
class FakeLive implements LiveDataSource {
  FakeLive(this.bodies);
  Map<String, String?> bodies;
  final cache = <String, CachedData>{};
  var fetches = 0;
  Completer<void>? gate;

  @override
  Future<String> fetch(String name) async {
    fetches++;
    await gate?.future;
    final b = bodies[name];
    if (b == null) throw StateError('offline');
    return b;
  }

  @override
  Future<CachedData?> readCache(String name) async => cache[name];

  @override
  Future<void> writeCache(String name, String body, {int? bundledHash}) async {
    cache[name] = CachedData(body: body, bundledHash: bundledHash);
  }
}

final _sponsorsJson = {
  'sponsors': [
    {'name': 'Acme Cloud', 'tier': 'Platinum', 'booth': '101'},
  ],
};

/// [scheduleJson] with t1 renamed and moved, t2 dropped and n1 added.
Map<String, dynamic> _newSchedule({
  String fetchedAt = '2026-11-10T08:00:00-07:00',
}) {
  final sessions = [
    for (final s in scheduleJson['sessions'] as List)
      if ((s as Map)['id'] != 't2')
        s['id'] == 't1'
            ? {
                ...s,
                'title': 'Scaling CI on Kubernetes (moved)',
                'start': '2026-11-10T15:00:00-07:00',
                'end': '2026-11-10T15:30:00-07:00',
              }
            : s,
    session(
      'n1',
      '2026-11-10T16:00:00-07:00',
      '2026-11-10T16:30:00-07:00',
      title: 'Late addition',
    ),
  ];
  return {...scheduleJson, 'fetchedAt': fetchedAt, 'sessions': sessions};
}

Map<String, String?> _allFiles() => {
  'schedule.json': jsonEncode(_newSchedule()),
  'details.json': jsonEncode(detailsJson),
  'sponsors.json': jsonEncode(_sponsorsJson),
  'happenings.json': jsonEncode(happeningsJson),
};

Future<AppState> _state({
  LiveDataSource? live,
  DateTime Function()? clock,
  Map<String, Object> prefs = const {},
  List<Sponsor>? sponsors,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(
    data: ConferenceData(
      schedule: testSchedule(),
      venue: testVenue(),
      happenings: testHappenings(),
      info: ConferenceInfo.fromJson({}),
      versions: {
        'schedule.json': DateTime.parse('2026-11-09T09:00:00-07:00'),
        'happenings.json': null,
      },
    ),
    prefs: await SharedPreferences.getInstance(),
    notifications: NoopNotificationService(),
    clock: clock ?? () => DateTime.utc(2026, 11, 10, 17),
    details: testDetails(),
    sponsors: sponsors ?? const [],
    live: live,
  );
}

Future<void> _pump(WidgetTester tester, AppState app, {int tab = 0}) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KubeConApp(state: app, initialTab: tab));
  await tester.pumpAndSettle();
}

/// Pulls the visible list of [screen] down and waits for the snack.
Future<void> _pull(WidgetTester tester, Type screen) async {
  final target = find.descendant(
    of: find.byType(screen),
    matching: find.byType(LiveRefresh),
  );
  expect(target, findsOneWidget);
  await tester.fling(target, const Offset(0, 400), 1200);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('AppState.refresh', () {
    test('applies new data, saves it and reschedules reminders', () async {
      final live = FakeLive(_allFiles());
      final app = await _state(
        live: live,
        prefs: {
          'saved_sessions': ['t1', 't2'],
          'notifications_enabled': true,
        },
      );
      final notes = app.notifications as NoopNotificationService;
      final r = await app.refresh();
      expect(r.updated, 4);
      expect(r.failed, 0);
      expect(r.offline, isFalse);
      expect(refreshMessage(r), 'Updated 10:00 AM');
      expect(app.lastRefreshed, r.at);
      expect(app.data.session('t1')!.title, 'Scaling CI on Kubernetes (moved)');
      expect(app.data.session('n1'), isNotNull);
      expect(app.sponsors.single.name, 'Acme Cloud');
      expect(
        app.data.versions['schedule.json'],
        DateTime.parse('2026-11-10T08:00:00-07:00'),
      );
      // t2 is gone from the new data: still saved, but not listed.
      expect(app.saved, containsAll(['t1', 't2']));
      expect(app.savedSessions.map((s) => s.id), ['t1']);
      // The reminder follows the moved session.
      expect(
        notes.scheduled.where((x) => x.title.contains('(moved)')),
        isNotEmpty,
      );
      await Future<void>.delayed(Duration.zero);
      expect(live.cache.keys, containsAll(liveDataFiles));
    });

    test('offline keeps the loaded data', () async {
      final live = FakeLive({});
      final app = await _state(live: live);
      final before = app.data;
      final r = await app.refresh();
      expect(r.offline, isTrue);
      expect(r.failed, 4);
      expect(refreshMessage(r), 'Offline — showing saved schedule');
      expect(identical(app.data, before), isTrue);
      expect(app.lastRefreshed, isNull);
    });

    test('no live source reports offline', () async {
      final app = await _state();
      expect(app.canRefresh, isFalse);
      expect((await app.refresh()).offline, isTrue);
    });

    test('a broken or older schedule never replaces the loaded one', () async {
      final live = FakeLive({
        'schedule.json': jsonEncode({...scheduleJson, 'sessions': []}),
        'happenings.json': '{"oops":',
      });
      final app = await _state(live: live);
      var r = await app.refresh();
      expect(r.offline, isTrue);
      expect(app.data.session('t2'), isNotNull);

      live.bodies = {
        'schedule.json': jsonEncode(
          _newSchedule(fetchedAt: '2026-11-01T08:00:00-07:00'),
        ),
      };
      r = await app.refresh();
      // Fetched fine, but older than what is loaded: kept as is.
      expect(r.updated, 1);
      expect(app.data.session('t2'), isNotNull);
      expect(live.cache, isEmpty);
    });

    test('concurrent refreshes share one fetch', () async {
      final live = FakeLive(_allFiles())..gate = Completer<void>();
      final app = await _state(live: live);
      final a = app.refresh(), b = app.refresh();
      expect(app.refreshing, isTrue);
      live.gate!.complete();
      expect(identical(await a, await b), isTrue);
      expect(live.fetches, liveDataFiles.length);
      expect(app.refreshing, isFalse);
    });

    test('autoRefresh waits 30 minutes between attempts', () async {
      var t = DateTime.utc(2026, 11, 10, 17);
      final live = FakeLive(_allFiles());
      final app = await _state(live: live, clock: () => t);
      await app.autoRefresh();
      expect(live.fetches, 4);
      t = t.add(const Duration(minutes: 10));
      await app.autoRefresh();
      expect(live.fetches, 4);
      t = t.add(const Duration(minutes: 25));
      await app.autoRefresh();
      expect(live.fetches, 8);
    });
  });

  group('cached data at start', () {
    const bundled = '{"fetchedAt":"2026-11-09T09:00:00-07:00","sessions":[1]}';
    const newer = '{"fetchedAt":"2026-11-10T09:00:00-07:00","sessions":[2]}';

    test('a newer saved copy wins, an older one does not', () async {
      final live = FakeLive({});
      live.cache['x.json'] = const CachedData(body: newer);
      var r = await loadPreferred(
        'x.json',
        bundled: () async => bundled,
        parse: (s) => s,
        live: live,
      );
      expect(r!.fromCache, isTrue);
      live.cache['x.json'] = CachedData(body: bundled.replaceAll('09T', '01T'));
      r = await loadPreferred(
        'x.json',
        bundled: () async => bundled,
        parse: (s) => s,
        live: live,
      );
      expect(r!.fromCache, isFalse);
    });

    test('without versions the copy wins only for the same bundle', () {
      final c = CachedData(body: '{"items":[]}', bundledHash: fingerprint('a'));
      expect(preferCached(c, 'a'), isTrue);
      expect(preferCached(c, 'b'), isFalse);
    });

    test('a broken saved copy falls back to the bundled one', () async {
      final live = FakeLive({});
      live.cache['x.json'] = const CachedData(body: newer);
      final r = await loadPreferred<String>(
        'x.json',
        bundled: () async => bundled,
        parse: (s) => s == newer ? throw const FormatException() : s,
        live: live,
      );
      expect(r!.raw, bundled);
    });
  });

  group('pull to refresh', () {
    for (final (name, tab, screen) in [
      ('Schedule', HomeTabs.schedule, ScheduleScreen),
      ('Now', HomeTabs.now, NowScreen),
      ('Saved (empty)', HomeTabs.saved, SavedScreen),
      ('Expo', HomeTabs.expo, ExpoScreen),
    ]) {
      testWidgets('$name shows when it updated', (tester) async {
        final live = FakeLive(_allFiles());
        final app = await _state(
          live: live,
          sponsors: Sponsor.listFromJson(_sponsorsJson),
        );
        await _pump(tester, app, tab: tab);
        await _pull(tester, screen);
        expect(live.fetches, 4);
        expect(find.text('Updated 10:00 AM'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('offline says the saved schedule is shown', (tester) async {
      final app = await _state(live: FakeLive({}));
      await _pump(tester, app, tab: HomeTabs.saved);
      await _pull(tester, SavedScreen);
      expect(find.text('Offline — showing saved schedule'), findsOneWidget);
    });

    testWidgets('Saved survives a saved session vanishing', (tester) async {
      final app = await _state(
        live: FakeLive(_allFiles()),
        prefs: {
          'saved_sessions': ['t2'],
        },
      );
      await _pump(tester, app, tab: HomeTabs.saved);
      expect(find.text('Session t2'), findsOneWidget);
      await _pull(tester, SavedScreen);
      expect(find.text('Session t2'), findsNothing);
      expect(find.text('No saved sessions yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('end of day', () {
    test('opens on today while anything is left, then the next day', () async {
      expect((await _state()).openingDayIndex, 1); // Tue 10, 10:00 AM
      // Tue 10, 9:00 PM: sessions and happenings are over.
      final late = await _state(clock: () => DateTime.utc(2026, 11, 11, 4));
      expect(late.openingDayIndex, 2);
      // Tue 10, 7:15 PM: the evening reception is still on.
      final evening = await _state(
        clock: () => DateTime.utc(2026, 11, 11, 2, 15),
      );
      expect(evening.openingDayIndex, 1);
      // Last day stays the last day.
      final last = await _state(clock: () => DateTime.utc(2026, 11, 13, 6));
      expect(last.openingDayIndex, 3);
    });

    testWidgets('Schedule opens on the next day; Today shows the wrap card', (
      tester,
    ) async {
      final app = await _state(clock: () => DateTime.utc(2026, 11, 11, 4));
      await _pump(tester, app);
      // Wed 11 is open.
      expect(find.text('Session w1'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text("That's a wrap for today"), findsOneWidget);
      await tester.tap(find.text('See Wed 11'));
      await tester.pumpAndSettle();
      expect(find.text('Session w1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no wrap card while sessions are still to come', (
      tester,
    ) async {
      final app = await _state();
      await _pump(tester, app);
      expect(find.text("That's a wrap for today"), findsNothing);
    });
  });
}
