import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/directions_screen.dart';
import 'package:kubecon_companion/screens/now_screen.dart';
import 'package:kubecon_companion/services/location_service.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<AppState> makeState({
  Map<String, Object> prefs = const {},
  bool withMap = true,
  bool withDetails = true,
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
      officialMap: withMap ? testOfficialMap() : null,
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

    await tester.tap(find.text('Scaling CI on Kubernetes'));
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
        home: DirectionsScreen(roomId: 'l1-hall-de', locate: locate),
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
      home: const DirectionsScreen(roomId: 'offsite-hotel'),
    );
    expect(find.text('Example Hotel'), findsOneWidget);
    expect(find.text('4 min walk'), findsOneWidget);
    expect(find.text('Open in maps'), findsOneWidget);
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
}
