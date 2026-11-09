import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/directions.dart';
import 'package:kubecon_companion/data/ics.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/session_detail_screen.dart';
import 'package:kubecon_companion/services/calendar_export.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// Unfolds and splits into logical content lines.
List<String> _lines(String ics) =>
    ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

void main() {
  final venue = testVenue();
  final schedule = testSchedule();
  Session byId(String id) => schedule.sessions.firstWhere((s) => s.id == id);
  ResolvedLocation loc(Session s) => resolveLocation(venue, s.roomId);

  test('escapes TEXT values', () {
    expect(
      icsEscape(
        r'a,b;c\d'
        '\nе\r\nf',
      ),
      r'a\,b\;c\\d\nе\nf',
    );
  });

  test('folds at 75 octets without splitting UTF-8', () {
    final line = 'DESCRIPTION:${'ü' * 100}';
    final folded = icsFold(line);
    for (final l in folded.split('\r\n')) {
      expect(utf8.encode(l).length, lessThanOrEqualTo(75));
    }
    expect(folded.replaceAll('\r\n ', ''), line);
    expect(icsFold('SHORT:x'), 'SHORT:x');
  });

  test('UTC date-times', () {
    expect(
      icsDateTime(DateTime.parse('2026-11-10T11:30:00-07:00')),
      '20261110T183000Z',
    );
  });

  test('VEVENT for a room session', () {
    final s = byId('t1');
    final ics = buildIcs([
      icsEventFor(s, loc(s)),
    ], stamp: DateTime.utc(2026, 11, 9, 8, 5, 3));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse);
    for (final l in ics.split('\r\n')) {
      expect(utf8.encode(l).length, lessThanOrEqualTo(75));
    }
    final lines = _lines(ics);
    expect(lines.first, 'BEGIN:VCALENDAR');
    expect(lines, contains('VERSION:2.0'));
    expect(lines, contains('UID:t1@kubecon.codemagic.app'));
    expect(lines, contains('DTSTAMP:20261109T080503Z'));
    expect(lines, contains('DTSTART:20261110T183000Z'));
    expect(lines, contains('DTEND:20261110T190000Z'));
    expect(lines, contains('SUMMARY:Scaling CI on Kubernetes'));
    final location = lines.firstWhere((l) => l.startsWith('LOCATION:'));
    expect(
      location,
      contains(' · Level 2 · Salt Palace Convention Center\\, '),
    );
    expect(
      lines,
      contains('DESCRIPTION:Speaker: Ada Example\\nhttps://example.com/t1'),
    );
    expect(lines, contains('URL:https://example.com/t1'));
    final alarm = lines.indexOf('BEGIN:VALARM');
    expect(lines.sublist(alarm, alarm + 5), [
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:Scaling CI on Kubernetes',
      'TRIGGER:-PT10M',
      'END:VALARM',
    ]);
  });

  test('off-site LOCATION uses the address; one VEVENT per session', () {
    final party = byId('party');
    expect(icsLocation(loc(party)), 'Example Hotel, 225 West 200 South');
    final ics = buildIcs([
      for (final s in schedule.sessions) icsEventFor(s, loc(s)),
    ], stamp: DateTime.utc(2026));
    expect('BEGIN:VEVENT'.allMatches(ics).length, schedule.sessions.length);
  });

  test('Hyatt rooms use the hotel address, not the Salt Palace', () {
    const hyatt = RoomLocation(
      Room(
        id: 'hyatt-l4-b',
        name: 'Regency Ballroom B-D',
        levelId: 'H4',
        x: 0,
        y: 0,
        w: 1,
        h: 1,
      ),
      Level(
        id: 'H4',
        name: 'Hyatt Regency - Level 4',
        order: 4,
        building: 'Hyatt Regency',
      ),
    );
    expect(
      icsLocation(hyatt),
      'Regency Ballroom B-D · Level 4 · $kHyattCalendarAddress',
    );
  });

  test('slug', () {
    expect(icsSlug('Scaling CI on Kubernetes!'), 'scaling-ci-on-kubernetes');
    expect(icsSlug('???'), 'session');
  });

  testWidgets('Add to calendar hands a .ics to the platform', (tester) async {
    final calls = <(String, String)>[];
    final original = deliverIcs;
    addTearDown(() => deliverIcs = original);
    deliverIcs =
        ({
          required String filename,
          required String content,
          Rect? origin,
        }) async {
          calls.add((filename, content));
        };
    SharedPreferences.setMockInitialValues({});
    final app = AppState(
      data: ConferenceData(
        schedule: testSchedule(),
        venue: testVenue(),
        happenings: const [],
        info: ConferenceInfo.fromJson({}),
      ),
      prefs: await SharedPreferences.getInstance(),
      notifications: NoopNotificationService(),
      clock: () => DateTime.utc(2026, 11, 10, 17),
      details: testDetails(),
    );
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      KubeConApp(
        state: app,
        home: const SessionDetailScreen(sessionId: 't1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to calendar'));
    await tester.pumpAndSettle();
    expect(calls.single.$1, 'kubecon-scaling-ci-on-kubernetes.ics');
    expect(calls.single.$2, contains('UID:t1@kubecon.codemagic.app'));

    deliverIcs = ({
      required String filename,
      required String content,
      Rect? origin,
    }) => Future.error(StateError('no share'));
    await tester.tap(find.text('Add to calendar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not open the calendar file on this device.'),
      findsOneWidget,
    );
  });
}
