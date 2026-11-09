import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/directions_screen.dart';
import 'package:kubecon_companion/screens/now_screen.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<AppState> makeState({Map<String, Object> prefs = const {}}) async {
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
    ),
    prefs: await SharedPreferences.getInstance(),
    notifications: NoopNotificationService(),
    // 10:00 AM MST on Tue Nov 10.
    clock: () => DateTime.utc(2026, 11, 10, 17),
  );
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

  testWidgets('search filters the day list', (tester) async {
    final state = await makeState();
    await pumpApp(tester, state);
    await tester.enterText(find.byType(TextField), 'scaling');
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
  });

  testWidgets('directions show numbered steps and a level change', (
    tester,
  ) async {
    final state = await makeState();
    await pumpApp(
      tester,
      state,
      home: const DirectionsScreen(roomId: 'l2-250'),
    );
    expect(find.text('Room 250 A-C'), findsOneWidget);
    expect(find.text('Show on map'), findsOneWidget);
    expect(find.text('1 level change'), findsOneWidget);
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
    expect(find.text('L1'), findsOneWidget);
    expect(find.text('L2'), findsOneWidget);

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
