import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/widgets/app_bar_title.dart';
import 'package:kubecon_companion/widgets/session_tile.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/official_map.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/outdoor/outdoor_map.dart';
import 'package:kubecon_companion/screens/directions_screen.dart';
import 'package:kubecon_companion/screens/map_screen.dart';
import 'package:kubecon_companion/screens/now_screen.dart';
import 'package:kubecon_companion/screens/schedule_screen.dart';
import 'package:kubecon_companion/screens/session_detail_screen.dart';
import 'package:kubecon_companion/screens/tagged_sessions_screen.dart';
import 'package:kubecon_companion/services/location_service.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/common.dart';
import 'package:kubecon_companion/widgets/outdoor_map_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'outdoor_fixture.dart';

Future<AppState> makeState({
  Map<String, Object> prefs = const {},
  bool withMap = true,
  bool withDetails = true,
  OfficialMap? map,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(
    data: ConferenceData(
      schedule: testSchedule(),
      venue: testVenue(),
      happenings: testHappenings(),
      info: ConferenceInfo.fromJson({
        'emergency': 'Dial 911',
        'links': [
          {'title': 'Official schedule', 'url': 'https://example.com'},
        ],
      }),
      officialMap: withMap ? (map ?? testOfficialMap()) : null,
    ),
    prefs: await SharedPreferences.getInstance(),
    notifications: NoopNotificationService(),
    // 10:00 AM MST on Tue Nov 10.
    clock: () => DateTime.utc(2026, 11, 10, 17),
    details: withDetails ? testDetails() : null,
  );
}

/// Serves details.json from memory, or fails, for [AppState.loadDetails].
class _DetailsBundle extends CachingAssetBundle {
  _DetailsBundle({this.fail = false});
  final bool fail;
  final gate = Completer<void>();

  @override
  Future<ByteData> load(String key) async {
    await gate.future;
    if (fail || key != 'assets/data/details.json') {
      throw FlutterError('Unable to load asset: $key');
    }
    final bytes = utf8.encode(jsonEncode(detailsJson));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

Future<void> pumpApp(
  WidgetTester tester,
  AppState state, {
  Widget? home,
}) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KubeConApp(state: state, home: home));
  await tester.pumpAndSettle();
}

/// Pumps frames for [seconds] without waiting for endless animations.
Future<void> pumpFor(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('schedule opens on today, saves a session, shows detail', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(tester, state);

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);
    expect(find.text('Session w1'), findsNothing); // next day

    await tester.tap(find.byTooltip('Save').first);
    await tester.pump();
    expect(state.saved, hasLength(1));

    // After saving, the session also shows in the "Up next" banner; tap the list tile.
    await tester.tap(
      find.descendant(
        of: find.byType(SessionTile),
        matching: find.text('Scaling CI on Kubernetes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Before you go'), findsOneWidget);
    expect(find.text('Laptop with kind installed'), findsOneWidget);
    expect(find.text('Ada Example'), findsOneWidget);
    expect(find.text('Room 250 A-C'), findsOneWidget);
  });

  testWidgets('session detail shows a placeholder until details load', (
    tester,
  ) async {
    final state = await makeState(withDetails: false);
    expect(state.detailsStatus, DetailsStatus.loading);
    final bundle = _DetailsBundle();
    final loading = state.loadDetails(bundle);
    await pumpApp(tester, state);

    await tester.tap(find.text('Scaling CI on Kubernetes'));
    await tester.pumpAndSettle();
    // Schedule data is there at once: title, room, save and reminder.
    expect(find.text('Room 250 A-C'), findsOneWidget);
    expect(find.text('Add reminder'), findsOneWidget);
    expect(find.text('Ada Example'), findsOneWidget);
    expect(find.text('Loading details…'), findsOneWidget);
    expect(find.text('About t1'), findsNothing);
    expect(find.text('Builds things.'), findsNothing);

    bundle.gate.complete();
    await tester.runAsync(() => loading);
    await tester.pumpAndSettle();
    expect(state.detailsStatus, DetailsStatus.loaded);
    expect(find.text('Loading details…'), findsNothing);
    expect(find.text('About t1'), findsOneWidget);
    expect(find.text('Before you go'), findsOneWidget);
    expect(find.text('Laptop with kind installed'), findsOneWidget);
    // The speaker card sits further down the (lazy) page.
    await tester.scrollUntilVisible(
      find.text('LinkedIn'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Builds things.'), findsOneWidget);
    expect(find.text('LinkedIn'), findsOneWidget);
  });

  testWidgets('session detail still works when details fail to load', (
    tester,
  ) async {
    final state = await makeState(withDetails: false);
    final bundle = _DetailsBundle(fail: true)..gate.complete();
    await tester.runAsync(() => state.loadDetails(bundle));
    expect(state.detailsStatus, DetailsStatus.failed);
    await pumpApp(tester, state);

    await tester.tap(find.text('Scaling CI on Kubernetes'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Room 250 A-C'), findsOneWidget);
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
    expect(state.isReminded('t1'), isTrue);
    expect(state.upcomingReminders.map((r) => r.sessionId), contains('t1'));
  });

  testWidgets('search filters the day list', (tester) async {
    final state = await makeState();
    await pumpApp(tester, state);
    await tester.enterText(find.byType(TextField), 'scaling');
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
  });

  testWidgets('map directions page through steps on the venue map', (
    tester,
  ) async {
    final state = await makeState();
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The route animates forever, so pump frames instead of settling.
    await tester.pumpWidget(
      KubeConApp(
        state: state,
        home: DirectionsScreen(
          roomId: 'l2-250',
          locate: () async => const LocationFailure('No location in tests'),
        ),
      ),
    );
    await pumpFor(tester, 1);
    expect(find.text('To 250 A-C'), findsOneWidget);
    expect(find.text('From 200 South entrance'), findsOneWidget);
    expect(find.textContaining('min walk'), findsOneWidget);
    expect(find.textContaining('Step 1 of'), findsOneWidget);
    expect(find.text('Pass Badge Pick-Up on your left.'), findsOneWidget);

    await tester.tap(find.byTooltip('Next step'));
    await pumpFor(tester, 1);
    expect(find.text('Take the escalator up to Level 2'), findsOneWidget);
    expect(find.text('North Foyer escalators'), findsOneWidget);
    await pumpFor(tester, 2); // level toast fades

    await tester.tap(find.text('Step-free'));
    await pumpFor(tester, 1);
    await tester.tap(find.byTooltip('Next step'));
    await pumpFor(tester, 1);
    expect(find.text('Take the elevator up to Level 2'), findsOneWidget);
    await pumpFor(tester, 2);
  });

  testWidgets('denied location keeps the current start point', (tester) async {
    final state = await makeState();
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      KubeConApp(
        state: state,
        home: DirectionsScreen(
          roomId: 'l1-hall-de',
          locate: () async => const LocationFailure('Permission denied test'),
        ),
      ),
    );
    await pumpFor(tester, 1);
    // The automatic attempt on open fails quietly and offers a retry.
    expect(find.text('Permission denied test'), findsNothing);
    expect(find.text('From 200 South entrance'), findsOneWidget);
    expect(find.text('Use my location'), findsOneWidget);
    await tester.tap(find.text('From 200 South entrance'));
    await pumpFor(tester, 1);
    expect(find.text('West Temple entrance'), findsOneWidget);
    await tester.tap(find.text('Use my location').last);
    await pumpFor(tester, 1);
    expect(find.text('Permission denied test'), findsOneWidget);
    expect(find.text('From 200 South entrance'), findsOneWidget);
    await pumpFor(tester, 5);
  });

  Future<void> openDirections(
    WidgetTester tester,
    AppState state,
    LocationProvider locate,
  ) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      KubeConApp(
        state: state,
        home: DirectionsScreen(
          roomId: 'l1-hall-de',
          locate: locate,
          positions: () => const Stream.empty(),
          permitted: () async => false,
        ),
      ),
    );
    await pumpFor(tester, 1);
  }

  testWidgets('a fix inside the venue starts from the nearest spot', (
    tester,
  ) async {
    final state = await makeState();
    await openDirections(
      tester,
      state,
      () async => const LocationFix(40.7655, -111.8950, 20),
    );
    expect(find.text('Near 200 South entrance'), findsOneWidget);
    expect(
      find.text("Indoor GPS can't tell floors — tap to change"),
      findsOneWidget,
    );
    expect(find.textContaining('~'), findsNothing);
    await pumpFor(tester, 2);
  });

  testWidgets('a fix nearby adds an outdoor walk to the closest entrance', (
    tester,
  ) async {
    final state = await makeState();
    await openDirections(
      tester,
      state,
      () async => const LocationFix(40.7700, -111.8935, 25),
    );
    expect(find.text('Via West Temple entrance'), findsOneWidget);
    expect(
      find.textContaining('Walk to the West Temple entrance (about 4'),
      findsOneWidget,
    );
    expect(find.text('Open in maps'), findsOneWidget);
    await pumpFor(tester, 2);
  });

  testWidgets('a start picked by hand is remembered for the session', (
    tester,
  ) async {
    final state = await makeState();
    var calls = 0;
    Future<LocationResult> locate() async {
      calls++;
      return const LocationFix(40.7655, -111.8950, 20);
    }

    await openDirections(tester, state, locate);
    expect(calls, 1);
    await tester.tap(find.text('Near 200 South entrance'));
    await pumpFor(tester, 1);
    await tester.tap(find.text('West Temple entrance'));
    await pumpFor(tester, 1);
    expect(find.text('From West Temple entrance'), findsOneWidget);
    expect(state.directionsStart?.nodeId, 'sp-entrance-west-temple');

    await tester.pumpWidget(const SizedBox());
    await openDirections(tester, state, locate);
    expect(calls, 1);
    expect(find.text('From West Temple entrance'), findsOneWidget);
    await pumpFor(tester, 2);
  });

  testWidgets('rooms not on the official map fall back to text steps', (
    tester,
  ) async {
    final state = await makeState(withMap: false);
    await pumpApp(
      tester,
      state,
      home: const DirectionsScreen(roomId: 'l2-250'),
    );
    expect(find.text('Room 250 A-C'), findsOneWidget);
    expect(find.textContaining('Change level'), findsOneWidget);
  });

  testWidgets('off-site directions offer an open-in-maps fallback', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: DirectionsScreen(
        roomId: 'offsite-hotel',
        outdoorLoader: (_) async => null,
      ),
    );
    expect(find.text('Example Hotel'), findsOneWidget);
    expect(find.text('4 min walk'), findsOneWidget);
    expect(find.text('Open in maps'), findsOneWidget);
    expect(find.text('Turn right'), findsOneWidget);
  });

  Future<void> openOffsite(
    WidgetTester tester,
    AppState state, {
    LocationProvider? locate,
    Stream<LocationFix> Function()? positions,
  }) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final map = OutdoorMap.fromJson(outdoorFixture());
    // The route animates forever, so pump frames instead of settling.
    await tester.pumpWidget(
      KubeConApp(
        state: state,
        home: DirectionsScreen(
          roomId: 'offsite-hotel',
          locate:
              locate ?? () async => const LocationFailure('No location here'),
          positions: positions ?? () => const Stream.empty(),
          outdoorLoader: (_) async => map,
        ),
      ),
    );
    await pumpFor(tester, 1);
  }

  testWidgets('off-site directions are interactive on our street map', (
    tester,
  ) async {
    final state = await makeState();
    await openOffsite(tester, state);
    expect(find.byType(OutdoorMapView), findsOneWidget);
    expect(find.text('Example Hotel'), findsOneWidget);
    expect(find.text('Off-site'), findsOneWidget);
    expect(find.text('From the North entrance'), findsOneWidget);
    expect(find.text('Head east on Third Ave'), findsOneWidget);
    expect(find.textContaining('Step 1 of 2'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('Open in maps'), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsOneWidget);

    await tester.tap(find.byTooltip('Next step'));
    await pumpFor(tester, 1);
    expect(find.text('Arrive at Example Hotel on your left'), findsOneWidget);

    // The old written steps stay available, collapsed.
    await tester.ensureVisible(find.text('Written directions'));
    await tester.tap(find.text('Written directions'));
    await pumpFor(tester, 1);
    expect(find.text('Exit onto 200 South'), findsOneWidget);

    // Change the start to another exit.
    await tester.ensureVisible(find.text('From the North entrance'));
    await pumpFor(tester, 1);
    await tester.tap(find.text('From the North entrance'));
    await pumpFor(tester, 1);
    await tester.tap(find.text('South entrance'));
    await pumpFor(tester, 1);
    expect(find.text('From the South entrance'), findsOneWidget);
    expect(find.text('Head north on Main'), findsOneWidget);
  });

  testWidgets('off-site directions follow live location to arrival', (
    tester,
  ) async {
    final state = await makeState();
    final fixes = StreamController<LocationFix>();
    addTearDown(fixes.close);
    LocationFix at(double east, double north) {
      final g = fxGeo(east, north);
      return LocationFix(g[0], g[1], 10);
    }

    await openOffsite(
      tester,
      state,
      locate: () async => at(205, 60),
      positions: () => fixes.stream,
    );
    expect(find.text('From your location'), findsOneWidget);
    expect(find.text('Head north on Second'), findsOneWidget);

    // Wander off: rerouted after two fixes.
    fixes.add(at(300, 100));
    await pumpFor(tester, 1);
    fixes.add(at(302, 100));
    await pumpFor(tester, 1);
    expect(find.text('Rerouted'), findsOneWidget);
    await pumpFor(tester, 2);

    fixes.add(at(105, 202));
    await pumpFor(tester, 1);
    expect(find.text('You have arrived'), findsWidgets);

    // Closing the screen stops listening.
    await tester.pumpWidget(const SizedBox());
    expect(fixes.hasListener, isFalse);
  });

  testWidgets('unknown rooms show the raw location text', (tester) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: const DirectionsScreen(roomId: 'unknown-room'),
    );
    expect(find.text('Unknown Room'), findsOneWidget);
  });

  testWidgets('tapping the title banner goes back to the schedule', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(tester, state);

    await tester.tap(find.text('Expo'));
    await tester.pumpAndSettle();
    expect(find.text('Search sponsors, booths, topics'), findsOneWidget);

    await tester.tap(find.byType(AppBarTitle).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Search talks, speakers, companies'), findsOneWidget);
  });

  testWidgets('map, now and saved tabs render', (tester) async {
    final state = await makeState(
      prefs: {
        'saved_sessions': <String>['t1'],
      },
    );
    await pumpApp(tester, state);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Salt Palace'), findsOneWidget);
    expect(find.text('Hyatt'), findsOneWidget);
    expect(find.text('L1'), findsOneWidget);
    expect(find.text('L2'), findsNWidgets(2));
    expect(
      find.text('Venue map: KubeCon + CloudNativeCon / Linux Foundation'),
      findsOneWidget,
    );

    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on reminders'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Good to know'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(NowScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Good to know'), findsOneWidget);

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);
  });

  testWidgets('locate me shows the live dot chip and follows fixes', (
    tester,
  ) async {
    final map = OfficialMap.fromJson(
      jsonDecode(File('assets/data/official_map.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final state = await makeState(map: map);
    final fixes = StreamController<LocationFix>.broadcast();
    addTearDown(fixes.close);
    var asked = 0;
    await pumpApp(
      tester,
      state,
      home: MapScreen(
        locate: () async {
          asked++;
          return const LocationFix(40.76583, -111.89503, 12);
        },
        positions: () => fixes.stream,
      ),
    );
    expect(find.byTooltip('Locate me'), findsOneWidget);
    await tester.tap(find.byTooltip('Locate me'));
    await pumpFor(tester, 1);
    expect(asked, 1);
    expect(fixes.hasListener, isTrue);
    expect(
      find.text('You · near Badge Pick-Up · ±12 m · floor unknown'),
      findsOneWidget,
    );

    fixes.add(const LocationFix(40.76748, -111.89503, 30, heading: 90));
    await pumpFor(tester, 1);
    expect(
      find.text('You · near Room 150 · ±30 m · floor unknown'),
      findsOneWidget,
    );

    // Far away: off the map, with walking directions to the venue.
    fixes.add(const LocationFix(40.7608, -111.8910, 20));
    await pumpFor(tester, 1);
    expect(find.textContaining("You're about"), findsOneWidget);
    expect(find.text('Directions to the venue'), findsOneWidget);

    // Leaving the tab stops the stream; coming back restarts it.
    await tester.pumpWidget(
      KubeConApp(
        state: state,
        home: MapScreen(
          active: false,
          locate: () async => const LocationFailure('unused'),
          positions: () => fixes.stream,
        ),
      ),
    );
    await pumpFor(tester, 1);
    expect(fixes.hasListener, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(fixes.hasListener, isFalse);
  });

  testWidgets('a route pushed over the map pauses the live stream', (
    tester,
  ) async {
    final map = OfficialMap.fromJson(
      jsonDecode(File('assets/data/official_map.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final state = await makeState(map: map);
    final fixes = StreamController<LocationFix>.broadcast();
    addTearDown(fixes.close);
    await pumpApp(
      tester,
      state,
      home: MapScreen(
        locate: () async => const LocationFix(40.76583, -111.89503, 12),
        positions: () => fixes.stream,
      ),
    );
    await tester.tap(find.byTooltip('Locate me'));
    await pumpFor(tester, 1);
    expect(fixes.hasListener, isTrue);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('x'))),
    );
    await pumpFor(tester, 1);
    expect(fixes.hasListener, isFalse);

    nav.pop();
    await pumpFor(tester, 1);
    expect(fixes.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('denied location shows why and dims the locate button', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: MapScreen(
        locate: () async => const LocationFailure(
          'Location permission was not granted. Pick a start point instead.',
        ),
        positions: () => const Stream.empty(),
      ),
    );
    await tester.tap(find.byTooltip('Locate me'));
    await pumpFor(tester, 1);
    expect(find.text('Location permission was not granted.'), findsOneWidget);
    expect(
      find.byTooltip('Location unavailable, tap to retry'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.location_disabled), findsOneWidget);
  });

  testWidgets('saving turns the reminder on; it can be muted and stays saved', (
    tester,
  ) async {
    final state = await makeState();
    expect(state.isReminderOn('t1'), isFalse);
    await state.toggleSaved('t1');
    expect(state.isSaved('t1'), isTrue);
    expect(state.isReminderOn('t1'), isTrue);
    expect(state.upcomingReminders.any((r) => r.sessionId == 't1'), isTrue);

    expect(await state.toggleReminder('t1'), isFalse);
    expect(state.isSaved('t1'), isTrue);
    expect(state.isReminderOn('t1'), isFalse);
    expect(state.upcomingReminders.any((r) => r.sessionId == 't1'), isFalse);

    // Unsave + save again: reminder is back on by default.
    await state.toggleSaved('t1');
    await state.toggleSaved('t1');
    expect(state.isReminderOn('t1'), isTrue);
    state.dispose(); // cancels the reschedule debounce timer
  });

  testWidgets('tag pills on a session page list every session with that tag', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: const SessionDetailScreen(sessionId: 't1'),
    );
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Show all Observability sessions'),
      findsOneWidget,
    );
    semantics.dispose();

    // The track pill lists the whole track across all days, upcoming first.
    await tester.tap(find.text('Observability'));
    await tester.pumpAndSettle();
    expect(find.byType(TaggedSessionsScreen), findsOneWidget);
    expect(find.byType(ScheduleScreen), findsNothing);
    expect(find.text('6 sessions'), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Today · 11:30 AM'), findsOneWidget);

    final order = [
      'Scaling CI on Kubernetes',
      'Session t2',
      'Lunch',
      'Reception',
      'Session w1',
    ];
    // A tall viewport so the lazy list builds every row.
    tester.view.physicalSize = const Size(375 * 3, 3000 * 3);
    await tester.pumpAndSettle();
    final ys = [
      for (final title in order)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(SessionTile),
                matching: find.text(title),
              ),
            )
            .dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(ys.toSet(), hasLength(order.length));
    // The keynote at 9:00 has ended: collapsed at the bottom.
    expect(find.text('Session k1'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Already ended · 1 ended')).dy,
      greaterThan(ys.last),
    );
    await tester.tap(find.text('Already ended · 1 ended'));
    await tester.pumpAndSettle();
    expect(find.text('Session k1'), findsOneWidget);

    // Tapping a session there opens its page.
    await tester.tap(find.text('Session k1'));
    await tester.pumpAndSettle();
    expect(find.byType(TaggedSessionsScreen), findsNothing); // now offstage
    expect(find.text('About k1'), findsOneWidget);
  });

  testWidgets('type and level pills open their own lists', (tester) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: const SessionDetailScreen(sessionId: 't1'),
    );
    await tester.tap(find.text('Talk'));
    await tester.pumpAndSettle();
    expect(find.text('2 sessions'), findsOneWidget);
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beginner'));
    await tester.pumpAndSettle();
    expect(find.byType(TaggedSessionsScreen), findsOneWidget);
    expect(find.text('6 sessions'), findsOneWidget);
  });

  testWidgets('schedule filters still show upcoming-first results', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(tester, state);
    await tester.enterText(find.byType(TextField), 'session');
    await tester.pumpAndSettle();
    expect(find.text('3 results across all days'), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Already ended · 1 ended'), findsOneWidget);
    // Tile pills stay informational: the tile itself opens the session.
    final pill = tester.widget<Pill>(
      find
          .descendant(of: find.byType(SessionTile), matching: find.byType(Pill))
          .first,
    );
    expect(pill.onTap, isNull);
  });

  testWidgets('schedule filters are remembered between launches', (
    tester,
  ) async {
    final state = await makeState(
      prefs: {
        // 'gone' no longer matches any session and is dropped.
        'schedule_filter_types': <String>['workshop', 'gone'],
      },
    );
    await pumpApp(tester, state);
    expect(find.textContaining('across all days'), findsOneWidget);
    expect(find.text('Session w1'), findsOneWidget);
    expect(find.text('Scaling CI on Kubernetes'), findsNothing);
    expect(find.text('1'), findsOneWidget); // filter count badge

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(state.prefs!.getStringList('schedule_filter_types'), isEmpty);
  });

  testWidgets('session page links to the full schedule of its room', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: const SessionDetailScreen(sessionId: 't1'),
    );
    final link = find.textContaining('sessions in Room 250 A-C');
    expect(link, findsOneWidget);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(TaggedSessionsScreen), findsOneWidget);
    // The app bar shows the room name; the list includes the session itself.
    expect(find.text('Room 250 A-C'), findsWidgets);
    expect(find.text('Scaling CI on Kubernetes'), findsWidgets);
  });
}
