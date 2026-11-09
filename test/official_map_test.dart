import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/official_map.dart';

Object? _json(String path) => jsonDecode(File(path).readAsStringSync());

void main() {
  group('bundled official map', () {
    final map = OfficialMap.fromJson(
      _json('assets/data/official_map.json')! as Map<String, dynamic>,
    );
    final venue = Venue.fromJson(_json('assets/data/venue.json'));
    final schedule = ScheduleData.fromJson(_json('assets/data/sessions.json'));
    final planner = RoutePlanner(map);

    MapRoute? routeTo(String roomId, {bool stepFree = false}) {
      final room = venue.room(roomId)!;
      final door = map.doorFor(room.id, partOf: room.partOf);
      if (door == null) return null;
      return planner.route(
        fromNodeId: OfficialMap.mainEntranceId,
        toNodeId: door.id,
        destinationName: room.name,
        destinationRect: map.room(room.id, partOf: room.partOf)?.rect,
        stepFree: stepFree,
      );
    }

    test('has every panel and the shared nodes', () {
      expect(
        map.regions.map((r) => r.id),
        containsAll([
          'sp-L1',
          'sp-L2',
          'sp-L3',
          'hy-L2',
          'hy-L3',
          'hy-L4',
          'hy-L5',
        ]),
      );
      for (final id in [
        OfficialMap.mainEntranceId,
        OfficialMap.westTempleEntranceId,
        OfficialMap.hyattLobbyId,
        'hy-L2-elevators',
        'hy-L5-elevators',
      ]) {
        expect(map.node(id), isNotNull, reason: id);
      }
      expect(map.width, greaterThan(1000));
    });

    test('every session room is reachable from the 200 South entrance', () {
      final rooms = {
        for (final s in schedule.sessions)
          if (venue.room(s.roomId) != null) venue.room(s.roomId)!.id,
      };
      expect(rooms, isNotEmpty);
      for (final id in rooms) {
        final r = routeTo(id);
        expect(r, isNotNull, reason: id);
        expect(r!.steps.last.kind, RouteStepKind.arrive, reason: id);
        expect(r.minutes, greaterThan(0), reason: id);
      }
    });

    test('every venue room on the map is reachable', () {
      for (final room in venue.rooms) {
        if (map.room(room.id, partOf: room.partOf) == null) continue;
        expect(routeTo(room.id), isNotNull, reason: room.id);
      }
    });

    test('a level change produces an escalator or elevator step', () {
      final r = routeTo('l2-250-a-c')!;
      final change = r.steps.firstWhere((s) => s.isLevelChange);
      expect(
        change.kind,
        anyOf(RouteStepKind.escalator, RouteStepKind.elevator),
      );
      expect(change.title, contains('up to Level 2'));
      expect(r.levelChanges, greaterThanOrEqualTo(1));

      final hy = routeTo('hyatt-l4-regency-ballroom-b-d')!;
      expect(hy.steps.any((s) => s.isLevelChange), isTrue);
      expect(
        hy.steps.where((s) => s.isLevelChange).last.title,
        contains('Hyatt Level 4'),
      );
    });

    test('step-free routes avoid escalators and stairs', () {
      for (final id in [
        'l2-250-a-c',
        'l3-355-a',
        'hyatt-l4-regency-ballroom-a',
      ]) {
        final r = routeTo(id, stepFree: true)!;
        expect(
          r.steps.where(
            (s) =>
                s.kind == RouteStepKind.escalator ||
                s.kind == RouteStepKind.stairs,
          ),
          isEmpty,
          reason: id,
        );
        expect(
          r.steps.any((s) => s.kind == RouteStepKind.elevator),
          isTrue,
          reason: id,
        );
      }
    });

    test('same-level route has no level change', () {
      final r = routeTo('l1-hall-de')!;
      expect(r.levelChanges, 0);
      expect(r.steps.first.kind, RouteStepKind.walk);
    });

    test('nearest geo node picks the West Temple entrance', () {
      final west = map.node(OfficialMap.westTempleEntranceId)!;
      final hit = nearestGeoNode(map, west.lat!, west.lng! + 0.0001);
      expect(hit, isNotNull);
      expect(hit!.$1.id, OfficialMap.westTempleEntranceId);
      expect(hit.$2, lessThan(50));
    });
  });

  group('step building', () {
    // A tiny map: east along a corridor, turn right (south) to a door,
    // with an escalator up to level 2.
    OfficialMap tiny() => OfficialMap.fromJson({
      'width': 1000,
      'height': 1000,
      'regions': [
        {
          'id': 'sp-L1',
          'label': 'L1',
          'building': 'Salt Palace',
          'levelId': 'L1',
          'rect': [0, 0, 600, 500],
        },
        {
          'id': 'sp-L2',
          'label': 'L2',
          'building': 'Salt Palace',
          'levelId': 'L2',
          'rect': [0, 500, 600, 500],
        },
      ],
      'rooms': {
        'r1': {'x': 260, 'y': 220, 'w': 60, 'h': 60, 'regionId': 'sp-L1'},
        'r2': {'x': 120, 'y': 600, 'w': 60, 'h': 60, 'regionId': 'sp-L2'},
      },
      'nodes': [
        {'id': 'a', 'x': 0, 'y': 100, 'regionId': 'sp-L1', 'kind': 'entrance'},
        {
          'id': 'b',
          'x': 100,
          'y': 100,
          'regionId': 'sp-L1',
          'kind': 'junction',
        },
        {
          'id': 'c',
          'x': 200,
          'y': 100,
          'regionId': 'sp-L1',
          'kind': 'junction',
        },
        {
          'id': 'd',
          'x': 200,
          'y': 250,
          'regionId': 'sp-L1',
          'kind': 'junction',
          'label': 'the Foyer',
        },
        {
          'id': 'door-r1',
          'x': 250,
          'y': 250,
          'regionId': 'sp-L1',
          'kind': 'door',
        },
        {
          'id': 'esc1',
          'x': 100,
          'y': 150,
          'regionId': 'sp-L1',
          'kind': 'escalator',
        },
        {
          'id': 'lift1',
          'x': 0,
          'y': 150,
          'regionId': 'sp-L1',
          'kind': 'elevator',
        },
        {
          'id': 'esc2',
          'x': 100,
          'y': 550,
          'regionId': 'sp-L2',
          'kind': 'escalator',
        },
        {
          'id': 'lift2',
          'x': 0,
          'y': 550,
          'regionId': 'sp-L2',
          'kind': 'elevator',
        },
        {
          'id': 'door-r2',
          'x': 150,
          'y': 590,
          'regionId': 'sp-L2',
          'kind': 'door',
        },
      ],
      'edges': [
        {'from': 'a', 'to': 'b', 'kind': 'walk', 'hint': 'Pass Badge Pick-Up'},
        {'from': 'b', 'to': 'c', 'kind': 'walk'},
        {'from': 'c', 'to': 'd', 'kind': 'walk'},
        {'from': 'd', 'to': 'door-r1', 'kind': 'walk'},
        {'from': 'b', 'to': 'esc1', 'kind': 'walk'},
        {'from': 'a', 'to': 'lift1', 'kind': 'walk'},
        {
          'from': 'esc1',
          'to': 'esc2',
          'kind': 'escalator',
          'hint': 'North Foyer escalators',
        },
        {'from': 'lift1', 'to': 'lift2', 'kind': 'elevator'},
        {'from': 'esc2', 'to': 'door-r2', 'kind': 'walk'},
        {'from': 'lift2', 'to': 'door-r2', 'kind': 'walk'},
      ],
    });

    test('merges straight walks and names the turn', () {
      final map = tiny();
      final r = RoutePlanner(map).route(
        fromNodeId: 'a',
        toNodeId: 'door-r1',
        destinationName: 'Room 1',
        destinationRect: map.rooms['r1']!.rect,
        startName: 'the entrance',
      )!;
      expect(r.steps.map((s) => s.kind), [
        RouteStepKind.walk,
        RouteStepKind.walk,
        RouteStepKind.arrive,
      ]);
      expect(r.steps[0].points, hasLength(3)); // a-b-c merged
      expect(r.steps[0].title, startsWith('From the entrance'));
      expect(r.steps[0].hint, 'Pass Badge Pick-Up.');
      expect(r.steps[1].title, 'Turn right and walk about 150 m toward Room 1');
      // Heading south, the door is to the east: on your left.
      expect(r.steps.last.title, 'Arrive at Room 1 on your left');
    });

    test('escalator by default, elevator when step-free', () {
      final map = tiny();
      final normal = RoutePlanner(map)
          .route(fromNodeId: 'a', toNodeId: 'door-r2')!;
      final change = normal.steps.firstWhere((s) => s.isLevelChange);
      expect(change.kind, RouteStepKind.escalator);
      expect(change.title, 'Take the escalator up to Level 2');
      expect(change.hint, 'North Foyer escalators');
      expect(change.regionId, 'sp-L2');

      final free = RoutePlanner(map)
          .route(fromNodeId: 'a', toNodeId: 'door-r2', stepFree: true)!;
      expect(
        free.steps.firstWhere((s) => s.isLevelChange).kind,
        RouteStepKind.elevator,
      );

      final down = RoutePlanner(map)
          .route(fromNodeId: 'door-r2', toNodeId: 'a')!;
      final d = down.steps.firstWhere((s) => s.isLevelChange);
      expect(d.title, 'Take the escalator down to Level 1');
      expect(d.hint, isNull); // hint is written for the upward direction
    });

    test('turnName follows screen coordinates', () {
      expect(turnName(const Offset(1, 0), const Offset(0, 1)), 'right');
      expect(turnName(const Offset(1, 0), const Offset(0, -1)), 'left');
      expect(turnName(const Offset(1, 0), const Offset(1, 0.1)), 'straight');
    });
  });
}
