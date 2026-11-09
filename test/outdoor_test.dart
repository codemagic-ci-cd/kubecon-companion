import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/outdoor/outdoor_loader.dart';
import 'package:kubecon_companion/outdoor/outdoor_map.dart';
import 'package:kubecon_companion/outdoor/outdoor_nav.dart';
import 'package:kubecon_companion/outdoor/outdoor_route.dart';
import 'package:kubecon_companion/outdoor/outdoor_steps.dart';

import 'outdoor_fixture.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.body);
  final String? body;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    if (body == null || key != outdoorAsset) {
      throw StateError('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(body!)));
  }
}

void main() {
  final map = OutdoorMap.fromJson(outdoorFixture());
  Offset w(double east, double north) {
    final g = fxGeo(east, north);
    return map.project(g[0], g[1]);
  }

  void near(Offset a, Offset b, [double tol = 0.5]) =>
      expect((a - b).distance, lessThan(tol), reason: '$a vs $b');

  OutdoorTarget hotel() =>
      resolveTarget(map, id: 'offsite-hotel', name: 'Example Hotel')!;

  group('projection', () {
    test('local metres, y grows south', () {
      final a = w(0, 0), b = w(0, 100), c = w(100, 0);
      expect(b.dy - a.dy, closeTo(-100, 0.5));
      expect(c.dx - a.dx, closeTo(100, 0.5));
      expect(map.size.width, closeTo(1200, 2));
      near(a, Offset(map.size.width / 2, map.size.height / 2), 2);
    });

    test('distance to the box is 0 inside and grows outside', () {
      final inside = fxGeo(0, 0), outside = fxGeo(0, 1600);
      expect(map.projection.distanceToBox(inside[0], inside[1]), 0);
      expect(
        map.projection.distanceToBox(outside[0], outside[1]),
        closeTo(1000, 3),
      );
    });
  });

  group('snapping', () {
    test('snaps onto the middle of an edge, not just nodes', () {
      final s = map.snap(w(10, 50))!;
      expect(s.node, isNull);
      expect(s.edge, isNotNull);
      final e = map.edges[s.edge!];
      expect(map.nameOf(e.name), 'Main');
      near(s.pos, w(0, 50));
    });

    test('snaps to a node past the end of a street', () {
      final s = map.snap(w(-30, -30))!;
      expect(s.node, 0);
    });
  });

  group('routing', () {
    final router = OutdoorRouter(map);

    test('from a snapped point along streets to a node', () {
      final r = router.route(map.snap(w(5, 50))!, map.nodePoint(6))!;
      expect(r.metres, closeTo(250, 1));
      expect(r.minutes, 4);
      expect(r.legs.map((l) => map.nameOf(l.name)).toSet(), {
        'Main',
        'Third Ave',
      });
      near(r.start, w(0, 50));
      near(r.end, w(100, 200));
    });

    test('along a single edge', () {
      final r = router.route(map.snap(w(0, 20))!, map.snap(w(0, 80))!)!;
      expect(r.legs, hasLength(1));
      expect(r.metres, closeTo(60, 0.5));
    });

    test('unreachable points give no route', () {
      expect(router.route(map.nodePoint(0), map.nodePoint(7)), isNull);
    });

    test('steps cost 20% more than flat ground', () {
      final g = fxGeo(0, 0), b = fxGeo(100, 0), c = fxGeo(50, 30);
      final m = OutdoorMap.fromJson({
        'bbox': [
          fxGeo(-200, -200)[0],
          fxGeo(-200, -200)[1],
          fxGeo(200, 200)[0],
          fxGeo(200, 200)[1],
        ],
        'nodes': [g, b, c],
        'names': [],
        'edges': [
          [0, 1, -1, 3],
          [0, 2, -1, 1],
          [2, 1, -1, 1],
        ],
      });
      final r = OutdoorRouter(m).route(m.nodePoint(0), m.nodePoint(1))!;
      // 116.6 m on the path beats 100 m of steps (120 m of cost).
      expect(r.legs, hasLength(2));
      expect(r.metres, closeTo(116.6, 0.5));
    });

    test('distances and walking time', () {
      expect(formatMetres(3), '10 m');
      expect(formatMetres(118), '120 m');
      expect(formatMetres(1240), '1.2 km');
      expect(walkMinutes(10), 1);
      expect(walkMinutes(250), 4);
    });
  });

  group('steps', () {
    List<OutdoorStep> stepsFor(GraphPoint from, GraphPoint to, Offset dest) {
      final r = OutdoorRouter(map).route(from, to)!;
      return OutdoorStepBuilder(map).build(
        r,
        destinationName: 'Example Hotel',
        destination: dest,
        startHint: 'Leave the venue through the North entrance',
      );
    }

    test('head, turn and arrive with compass and side', () {
      final steps = stepsFor(
        map.snap(w(5, 50))!,
        map.nodePoint(6),
        w(100, 220),
      );
      expect(steps.map((s) => s.title), [
        'Head north on Main',
        'Turn right onto Third Ave',
        'Arrive at Example Hotel on your left',
      ]);
      expect(steps.first.hint, contains('North entrance'));
      expect(steps.first.distanceLabel, '150 m · 2 min');
      expect(steps[1].turn, TurnDirection.right);
      expect(steps.last.kind, OutdoorStepKind.arrive);
    });

    test('arriving with the venue on the right', () {
      final steps = stepsFor(map.nodePoint(4), map.nodePoint(6), w(100, 220));
      expect(steps.first.title, 'Head west on Third Ave');
      expect(steps.last.title, 'Arrive at Example Hotel on your right');
    });

    test('left turns', () {
      final steps = stepsFor(map.nodePoint(3), map.nodePoint(1), w(-5, 100));
      expect(steps.map((s) => s.title).take(2), [
        'Head west on First Ave',
        'Turn right onto Main',
      ]);
      final back = stepsFor(map.nodePoint(1), map.nodePoint(3), w(200, -20));
      expect(back.map((s) => s.title), [
        'Head south on Main',
        'Turn left onto First Ave',
        'Arrive at Example Hotel on your right',
      ]);
    });

    test('crossings name the street crossed, then continue', () {
      final steps = stepsFor(map.nodePoint(0), map.nodePoint(10), w(300, 20));
      expect(steps.map((s) => s.title), [
        'Head east on First Ave',
        'Cross Second',
        'Continue on First Ave',
        'Arrive at Example Hotel on your left',
      ]);
      expect(steps[1].kind, OutdoorStepKind.cross);
      expect(steps[1].distanceLabel, '20 m');
    });

    test('compass and turn helpers', () {
      expect(compassName(bearing(w(0, 0), w(0, 100))), 'north');
      expect(compassName(bearing(w(0, 0), w(100, 100))), 'northeast');
      expect(compassName(bearing(w(0, 0), w(-100, 0))), 'west');
      expect(turnAngle(350, 10), closeTo(20, 1e-9));
      expect(turnDirection(-90), TurnDirection.left);
      expect(turnDirection(35), TurnDirection.slightRight);
      expect(turnDirection(5), TurnDirection.straight);
    });
  });

  group('start selection', () {
    final target = hotel();

    test('resolves the destination and its building', () {
      near(target.point.pos, w(100, 200));
      expect(target.building?.name, 'Example Hotel');
    });

    test('no fix: the exit with the shortest walk', () {
      final s = chooseOutdoorStart(map, target.point);
      expect(s.kind, OutdoorStartKind.fallback);
      expect(s.reason, OutdoorFallbackReason.unavailable);
      expect(s.exit?.id, 'north');
      expect(s.label, 'From the North entrance');
    });

    test('inaccurate and far fixes fall back to the best exit', () {
      final p = fxGeo(300, 300);
      final bad = chooseOutdoorStart(
        map,
        target.point,
        lat: p[0],
        lng: p[1],
        accuracy: 400,
      );
      expect(bad.reason, OutdoorFallbackReason.inaccurate);
      expect(bad.exit?.id, 'north');
      final far = fxGeo(0, 5000);
      final tooFar = chooseOutdoorStart(
        map,
        target.point,
        lat: far[0],
        lng: far[1],
        accuracy: 10,
      );
      expect(tooFar.reason, OutdoorFallbackReason.tooFar);
    });

    test('at the venue: the exit closest by route', () {
      final p = fxGeo(-40, 20);
      final s = chooseOutdoorStart(
        map,
        target.point,
        lat: p[0],
        lng: p[1],
        accuracy: 20,
      );
      expect(s.kind, OutdoorStartKind.atVenue);
      // The south door is nearer as the crow flies; the north one is
      // the shorter walk.
      expect(s.exit?.id, 'north');
    });

    test('nearby: from the snapped position', () {
      final p = fxGeo(210, 100);
      final s = chooseOutdoorStart(
        map,
        target.point,
        lat: p[0],
        lng: p[1],
        accuracy: 20,
      );
      expect(s.kind, OutdoorStartKind.gps);
      expect(s.label, 'From your location');
      near(s.point.pos, w(200, 100));
      final plan = planWalk(map, s, target)!;
      expect(plan.route.metres, closeTo(200, 1));
      expect(plan.steps.first.title, 'Head north on Second');
    });

    test('a picked exit wins', () {
      final s = chooseOutdoorStart(map, target.point, exitId: 'south');
      expect(s.kind, OutdoorStartKind.picked);
      expect(s.exit?.id, 'south');
      expect(s.hint, 'Leave the venue through the South entrance');
    });
  });

  group('live guidance', () {
    NavTracker tracker() {
      final s = OutdoorStart(
        kind: OutdoorStartKind.gps,
        point: map.snap(w(0, 50))!,
      );
      final plan = planWalk(map, s, hotel())!;
      expect(plan.steps, hasLength(3));
      return NavTracker(plan.route, plan.steps);
    }

    test('advances near the end of a step', () {
      final t = tracker();
      expect(t.update(w(1, 120), 10), NavEvent.none);
      expect(t.step, 0);
      expect(t.update(w(2, 190), 10), NavEvent.advanced);
      expect(t.step, 1);
    });

    test('skips ahead when a step was walked past', () {
      final t = tracker();
      expect(t.update(w(50, 201), 10), NavEvent.advanced);
      expect(t.step, 1);
    });

    test('reroutes after two fixes off route', () {
      final t = tracker();
      expect(t.update(w(60, 100), 10), NavEvent.none);
      expect(t.update(w(1, 110), 10), NavEvent.none, reason: 'back on');
      expect(t.update(w(60, 100), 10), NavEvent.none);
      expect(t.update(w(62, 100), 10), NavEvent.reroute);
    });

    test('ignores imprecise fixes', () {
      final t = tracker();
      expect(t.update(w(80, 100), 300), NavEvent.none);
      expect(t.update(w(80, 100), 300), NavEvent.none);
      expect(t.step, 0);
    });

    test('arrives within 20 m of the destination', () {
      final t = tracker();
      expect(t.update(w(88, 205), 15), NavEvent.arrived);
      expect(t.arrived, isTrue);
      expect(t.step, 2);
      expect(t.update(w(0, 0), 15), NavEvent.none);
    });
  });

  group('loader', () {
    test(
      'missing asset gives null and is retried; success is cached',
      () async {
        expect(await loadOutdoorMap(_Bundle(null)), isNull);
        final ok = _Bundle(jsonEncode(outdoorFixture()));
        final a = await loadOutdoorMap(ok);
        final b = await loadOutdoorMap(ok);
        expect(a, isNotNull);
        expect(identical(a, b), isTrue);
        expect(ok.loads, 1);
      },
    );
  });

  group('bundled outdoor.json', () {
    final file = File(outdoorAsset);
    test('routes to every off-site venue from a venue exit', () {
      final real = OutdoorMap.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      final venue = Venue.fromJson(
        jsonDecode(File('assets/data/venue.json').readAsStringSync()),
      );
      expect(real.attribution, contains('OpenStreetMap'));
      expect(real.exits, isNotEmpty);
      expect(venue.offsite, isNotEmpty);
      for (final o in venue.offsite) {
        final t = resolveTarget(
          real,
          id: o.id,
          name: o.name,
          lat: o.lat,
          lng: o.lng,
        );
        expect(t, isNotNull, reason: o.id);
        final plan = planWalk(real, chooseOutdoorStart(real, t!.point), t);
        expect(plan, isNotNull, reason: o.id);
        expect(plan!.route.metres, lessThan(2000), reason: o.id);
        expect(plan.steps.last.kind, OutdoorStepKind.arrive, reason: o.id);
        for (final e in real.exits) {
          expect(
            OutdoorRouter(real).route(real.nodePoint(e.node), t.point),
            isNotNull,
            reason: '${e.id} -> ${o.id}',
          );
        }
      }
    }, skip: file.existsSync() ? false : 'outdoor.json not generated yet');

    test('walks on sidewalks, not down the middle of the road', () {
      final real = OutdoorMap.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      // Temple Square to Utah MOCA: South Temple has sidewalks both sides.
      final t = resolveTarget(real, id: 'offsite-utah-moca', name: 'MOCA')!;
      final start = chooseOutdoorStart(
        real,
        t.point,
        lat: 40.7703,
        lng: -111.8919,
        accuracy: 10,
      );
      final plan = planWalk(real, start, t)!;
      final onRoad = plan.route.legs
          .where((l) => l.kind == OutdoorEdgeKind.street)
          .fold(0.0, (a, l) => a + l.metres);
      expect(onRoad, lessThan(20));
      // Driveway crosswalks along South Temple are not "Cross South Temple".
      final titles = plan.steps.map((s) => s.title).toList();
      expect(
        titles.where((t) => t == 'Cross South Temple').length,
        lessThanOrEqualTo(1),
        reason: '$titles',
      );
      expect(titles, contains('Turn left onto West Temple'));
    }, skip: file.existsSync() ? false : 'outdoor.json not generated yet');
  });
}
