import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/agenda_link.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/official_map.dart';
import 'package:kubecon_companion/data/spot_link.dart';
import 'package:kubecon_companion/data/sponsors.dart';
import 'package:kubecon_companion/location/spot_place.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/directions_screen.dart';
import 'package:kubecon_companion/screens/home_shell.dart';
import 'package:kubecon_companion/screens/map_screen.dart';
import 'package:kubecon_companion/services/location_service.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/link_router.dart';
import 'package:kubecon_companion/widgets/spot_share.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kubecon_companion/outdoor/outdoor_map.dart';
import 'package:kubecon_companion/screens/outdoor_directions.dart';

import 'fixtures.dart';
import 'outdoor_fixture.dart';

/// 10:00 AM MST on Tue Nov 10.
final _now = DateTime.utc(2026, 11, 10, 17);

Future<AppState> _state({List<Sponsor> sponsors = const []}) async {
  SharedPreferences.setMockInitialValues({});
  return AppState(
    data: ConferenceData(
      schedule: testSchedule(),
      venue: testVenue(),
      happenings: testHappenings(),
      info: ConferenceInfo.fromJson({}),
      officialMap: testOfficialMap(),
    ),
    prefs: await SharedPreferences.getInstance(),
    notifications: NoopNotificationService(),
    clock: () => _now,
    details: testDetails(),
    sponsors: sponsors,
  );
}

Future<void> _pump(
  WidgetTester tester,
  AppState app, {
  Stream<Uri>? links,
  Widget? home,
  String? pendingSpot,
}) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    KubeConApp(
      state: app,
      links: links,
      home: home,
      pendingSpot: pendingSpot,
      initialTab: pendingSpot == null ? 0 : HomeTabs.map,
    ),
  );
}

SharedSpot _room({Duration ago = const Duration(minutes: 5), String? note}) =>
    SharedSpot(
      name: 'Alex',
      roomId: 'l1-hall-de',
      note: note,
      time: _now.subtract(ago),
    );

void main() {
  group('encode / decode', () {
    test('a room spot round-trips', () {
      final s = _room(note: 'at the Codemagic booth');
      final payload = encodeSpot(s);
      expect(payload, startsWith(kSpotPrefix));
      expect(RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(payload), isTrue);
      expect(decodeSpot(payload), s);
    });

    test('GPS is rounded to 5 decimals and round-trips', () {
      final s = SharedSpot(
        name: 'Tõnu 🚀',
        lat: 40.765834567,
        lng: -111.895031234,
        time: _now,
      );
      expect(s.lat, 40.76583);
      expect(s.lng, -111.89503);
      final back = decodeSpot(encodeSpot(s))!;
      expect(back, s);
      expect(back.name, 'Tõnu 🚀');
      expect(back.note, isNull);
      expect(back.isRoom, isFalse);
      expect(back.time, _now);
    });

    test('name and note are trimmed and clipped', () {
      final s = SharedSpot(
        name: '  ${'n' * 60}  ',
        roomId: 'x',
        note: '  ${'w ' * 100}',
        time: _now,
      );
      expect(s.name.length, kSpotNameMax);
      expect(s.note!.length, lessThanOrEqualTo(kSpotNoteMax));
      expect(decodeSpot(encodeSpot(s)), s);
    });

    test('spotLink puts it in ?at= on the web app', () {
      final s = _room();
      final link = spotLink(s);
      expect(link, startsWith('$kAppBaseUrl?at=v1.'));
      final uri = Uri.parse(link);
      expect(spotParamFrom(uri), encodeSpot(s));
      expect(decodeSpot(spotParamFrom(uri)!), s);
    });

    test('bad payloads decode to null without throwing', () {
      String b64(Object o) =>
          'v1.${base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '')}';
      for (final p in [
        '',
        'v1.',
        'v2.abc',
        'a1.AAAA',
        'v1.%%%',
        'v1.${'A' * 2000}',
        b64({'name': 'x'}),
        b64(['', 'room', '', 1]),
        b64(['A', 'room', '', 0]),
        b64(['A', 'room', '', 'yesterday']),
        b64(['A', '', '', 1]),
        b64(['A', 'r' * 200, '', 1]),
        b64([
          'A',
          [9100000, 0],
          '',
          1,
        ]),
        b64([
          'A',
          [0, 18100000],
          '',
          1,
        ]),
        b64([
          'A',
          [1.5, 2],
          '',
          1,
        ]),
        b64([
          'A',
          [1],
          '',
          1,
        ]),
        b64(['A', 42, '', 1]),
        b64(['A', 'room', 7, 1]),
      ]) {
        expect(decodeSpot(p), isNull, reason: p);
      }
      expect(spotParamFrom(Uri.parse('$kAppBaseUrl?at=')), isNull);
      expect(
        () => spotParamFrom(Uri.parse('$kAppBaseUrl?at=%zz')),
        returnsNormally,
      );
    });

    test('age, staleness and labels', () {
      expect(fmtSpotAge(Duration.zero), 'just now');
      expect(fmtSpotAge(const Duration(minutes: 12)), '12 min ago');
      expect(fmtSpotAge(const Duration(hours: 3)), '3 h ago');
      expect(fmtSpotAge(const Duration(hours: 2, minutes: 5)), '2 h 5 min ago');
      expect(fmtSpotAge(const Duration(days: 3)), '3 days ago');
      expect(_room().isStale(_now), isFalse);
      expect(
        _room(ago: const Duration(hours: 2, minutes: 1)).isStale(_now),
        isTrue,
      );
      // A clock ahead of ours is "just now", not negative.
      final ahead = SharedSpot(
        name: 'A',
        roomId: 'x',
        time: _now.add(const Duration(minutes: 3)),
      );
      expect(ahead.age(_now), Duration.zero);
    });
  });

  group('AppLink.parse', () {
    test('tells agendas, spots and other links apart', () {
      expect(
        AppLink.parse(Uri.parse(agendaLink(['w1']))),
        isA<AgendaAppLink>(),
      );
      expect(AppLink.parse(Uri.parse(spotLink(_room()))), isA<SpotAppLink>());
      expect(AppLink.parse(Uri.parse(kAppBaseUrl)), isNull);
      expect(AppLink.parse(Uri.parse('$kAppBaseUrl?tab=map')), isNull);
    });
  });

  group('placeSpot on the real venue map', () {
    final map = OfficialMap.fromJson(
      jsonDecode(File('assets/data/official_map.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final venue = Venue.fromJson(
      jsonDecode(File('assets/data/venue.json').readAsStringSync()),
    );
    final data = ConferenceData(
      schedule: ScheduleData.fromJson(const {}),
      venue: venue,
      happenings: const [],
      info: ConferenceInfo.fromJson({}),
      officialMap: map,
    );

    test('a room spot pins the room and routes to it', () {
      final p = placeSpot(
        data,
        SharedSpot(name: 'A', roomId: 'l1-hall-de', time: _now),
      );
      expect(p.pos, map.room('l1-hall-de')!.rect.center);
      expect(p.place, venue.room('l1-hall-de')!.name);
      expect(p.targetRoomId, 'l1-hall-de');
      expect(p.offVenue, isFalse);
    });

    test('a sponsor hall spot pins the hall', () {
      final p = placeSpot(
        data,
        SharedSpot(name: 'A', roomId: 'l1-halls-a-c-halls-1-5', time: _now),
      );
      expect(p.pos, isNotNull);
      expect(p.targetRoomId, 'l1-halls-a-c-halls-1-5');
    });

    test('an unknown room has no pin and no route', () {
      final p = placeSpot(
        data,
        SharedSpot(name: 'A', roomId: 'gone', time: _now),
      );
      expect(p.pos, isNull);
      expect(p.targetRoomId, isNull);
    });

    test('GPS in the venue is projected near a place, with a route', () {
      final p = placeSpot(
        data,
        SharedSpot(name: 'A', lat: 40.76583, lng: -111.89503, time: _now),
      );
      expect(p.offVenue, isFalse);
      expect(p.pos, isNotNull);
      expect(p.regionId, 'sp-L1');
      expect(p.place, 'Badge Pick-Up');
      final room = venue.room(p.targetRoomId)!;
      expect(map.doorFor(room.id, partOf: room.partOf), isNotNull);
    });

    test('GPS away from the venue is off the map', () {
      // Temple Square, about 600 m north.
      final near = placeSpot(
        data,
        SharedSpot(name: 'A', lat: 40.7707, lng: -111.8919, time: _now),
      );
      expect(near.offVenue, isTrue);
      expect(near.pos, isNull);
      expect(near.metresAway, greaterThan(150));
      // New York.
      final far = placeSpot(
        data,
        SharedSpot(name: 'A', lat: 40.7128, lng: -74.006, time: _now),
      );
      expect(far.offVenue, isTrue);
      expect(far.awayLabel, endsWith('km'));
    });
  });

  group('opening spot links', () {
    testWidgets('a native link opens the map with the pin card', (
      tester,
    ) async {
      final app = await _state();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await _pump(tester, app, links: links.stream);
      await tester.pumpAndSettle();
      expect(find.byType(SpotCard), findsNothing);
      final uri = Uri.parse(spotLink(_room(note: 'at the Codemagic booth')));
      links
        ..add(uri)
        ..add(uri);
      await tester.pumpAndSettle();
      final shell = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(shell.selectedIndex, HomeTabs.map);
      expect(
        find.text('Alex is here · near Hall DE (Keynotes) · shared 5 min ago'),
        findsOneWidget,
      );
      expect(find.text('at the Codemagic booth'), findsOneWidget);
      expect(find.textContaining('may have moved on'), findsNothing);

      await tester.tap(find.text('Directions'));
      // The route animates forever: pump a while instead of settling.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(DirectionsScreen), findsOneWidget);
      expect(
        tester.widget<DirectionsScreen>(find.byType(DirectionsScreen)).roomId,
        'l1-hall-de',
      );
    });

    testWidgets('an old spot warns, and the pin can be removed', (
      tester,
    ) async {
      final app = await _state();
      app.showSpot(_room(ago: const Duration(hours: 3)));
      await _pump(tester, app, home: const MapScreen());
      await tester.pumpAndSettle();
      expect(find.textContaining('shared 3 h ago'), findsOneWidget);
      expect(
        find.text('Shared over 2 hours ago. They may have moved on.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Remove pin'));
      await tester.pumpAndSettle();
      expect(find.byType(SpotCard), findsNothing);
      expect(app.sharedSpot.value, isNull);
    });

    testWidgets('a web launch link pins the spot', (tester) async {
      final app = await _state();
      await _pump(tester, app, pendingSpot: encodeSpot(_room()));
      await tester.pumpAndSettle();
      expect(find.byType(SpotCard), findsOneWidget);
      expect(app.sharedSpot.value, _room());
    });

    testWidgets('a broken spot link says so', (tester) async {
      final app = await _state();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await _pump(tester, app, links: links.stream);
      links.add(Uri.parse('$kAppBaseUrl?at=v1.broken'));
      await tester.pumpAndSettle();
      expect(find.text('That spot link is not valid.'), findsOneWidget);
      expect(app.sharedSpot.value, isNull);
    });

    testWidgets('a GPS spot off the venue says how far', (tester) async {
      final app = await _state();
      app.showSpot(
        SharedSpot(name: 'Sam', lat: 40.7707, lng: -111.8919, time: _now),
      );
      await _pump(tester, app, home: const MapScreen());
      await tester.pumpAndSettle();
      // The fixture map has no geo calibration: no distance, no pin.
      expect(find.text('Sam is here · shared just now'), findsOneWidget);
    });
  });

  group('directions to a GPS spot off the venue', () {
    testWidgets('inside the street map: walking directions there', (
      tester,
    ) async {
      final app = await _state();
      final g = fxGeo(200, 200);
      app.showSpot(SharedSpot(name: 'Sam', lat: g[0], lng: g[1], time: _now));
      await _pump(
        tester,
        app,
        home: MapScreen(
          outdoorLoader: (_) async => OutdoorMap.fromJson(outdoorFixture()),
          locate: () async => const LocationFailure('No location.'),
          positions: () => const Stream.empty(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Directions'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(OffsiteDirections), findsOneWidget);
      expect(find.text('To Sam'), findsOneWidget);
    });

    testWidgets('outside it: hands off to the maps app', (tester) async {
      final app = await _state();
      final spot = SharedSpot(
        name: 'Sam',
        lat: 40.7128,
        lng: -74.006,
        time: _now,
      );
      String? opened;
      await _pump(
        tester,
        app,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSpotDirections(
                context,
                placeSpot(app.data, spot),
                outdoorLoader: (_) async =>
                    OutdoorMap.fromJson(outdoorFixture()),
                open: (_, url) async => opened = url,
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.byType(OffsiteDirections), findsNothing);
      expect(
        opened,
        'https://www.google.com/maps/dir/?api=1'
        '&destination=40.7128,-74.006&travelmode=walking',
      );
    });
  });

  group('share sheet', () {
    testWidgets('pick a booth, get a link that pins its hall', (tester) async {
      final app = await _state(
        sponsors: [
          const Sponsor(
            id: 'codemagic',
            name: 'Codemagic',
            tier: 'Gold',
            booth: '115',
            hall: 'Hall DE',
            roomId: 'l1-hall-de',
          ),
        ],
      );
      await _pump(tester, app, home: const MapScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share my spot'));
      await tester.pumpAndSettle();
      expect(find.text('Add your name to get a link.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('spot-name')), 'Alex');
      await tester.tap(find.text('Pick a room / booth'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'codemagic');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codemagic'));
      await tester.pumpAndSettle();
      expect(find.text('Codemagic · Booth 115 · Hall DE'), findsOneWidget);
      final note = tester.widget<TextField>(
        find.byKey(const ValueKey('spot-note')),
      );
      expect(note.controller!.text, 'at the Codemagic booth');
      expect(find.byKey(const ValueKey('spot-qr')), findsOneWidget);
      final link = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      final spot = decodeSpot(spotParamFrom(Uri.parse(link))!)!;
      expect(spot.name, 'Alex');
      expect(spot.roomId, 'l1-hall-de');
      expect(spot.note, 'at the Codemagic booth');
      expect(spot.time, _now);

      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      // The name is remembered for next time.
      expect(app.spotName, 'Alex');
    });

    testWidgets('use my location shows where and level unknown', (
      tester,
    ) async {
      final map = OfficialMap.fromJson(
        jsonDecode(File('assets/data/official_map.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      SharedPreferences.setMockInitialValues({'spot_name': 'Kim'});
      final app = AppState(
        data: ConferenceData(
          schedule: testSchedule(),
          venue: testVenue(),
          happenings: testHappenings(),
          info: ConferenceInfo.fromJson({}),
          officialMap: map,
        ),
        prefs: await SharedPreferences.getInstance(),
        notifications: NoopNotificationService(),
        clock: () => _now,
        details: testDetails(),
        sponsors: const [],
      );
      await _pump(
        tester,
        app,
        home: MapScreen(
          locate: () async => const LocationFix(40.76583, -111.89503, 12),
          positions: () => const Stream.empty(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share my spot'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('spot-name')))
            .controller!
            .text,
        'Kim',
      );
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Near Badge Pick-Up · level unknown · ±12 m'),
        findsOneWidget,
      );
      final link = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      final spot = decodeSpot(spotParamFrom(Uri.parse(link))!)!;
      expect(spot.lat, 40.76583);
      expect(spot.lng, -111.89503);
    });

    testWidgets('location denied explains and keeps the room option', (
      tester,
    ) async {
      final app = await _state();
      await _pump(
        tester,
        app,
        home: MapScreen(
          locate: () async => const LocationFailure(
            'Location permission is off. Pick a start point instead.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share my spot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Location permission is off. Pick a room or booth instead.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spot-qr')), findsNothing);
    });
  });

  test('booth search resolves sponsors to their hall room', () {
    final rows = spotPlaceResults(testVenue(), [
      const Sponsor(
        id: 'a',
        name: 'Acme',
        tier: 'Gold',
        booth: '7',
        roomId: 'l1-hall-de',
      ),
      const Sponsor(id: 'b', name: 'Acme Two', tier: 'Gold', roomId: 'gone'),
    ], 'acme');
    expect(rows.map((r) => r.$2), ['Acme']);
    expect(rows.single.$4.roomId, 'l1-hall-de');
    expect(spotPlaceResults(testVenue(), const [], '').length, 2);
  });
}
