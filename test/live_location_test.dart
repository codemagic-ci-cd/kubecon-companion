import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/official_map.dart';
import 'package:kubecon_companion/location/geo_projection.dart';
import 'package:kubecon_companion/location/live_location.dart';
import 'package:kubecon_companion/services/location_service.dart';

import 'fixtures.dart';

void main() {
  final map = OfficialMap.fromJson(
    jsonDecode(File('assets/data/official_map.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final proj = GeoProjection.of(map)!;

  group('projection', () {
    test('fits every main-plan anchor within 25 m', () {
      expect(proj.residuals.length, greaterThanOrEqualTo(10));
      proj.residuals.forEach((id, r) {
        expect(r, lessThan(25), reason: id);
      });
      expect(proj.rmsResidual, lessThan(10));
      final worst = proj.residuals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      // ignore: avoid_print
      print(
        'projection: ${proj.residuals.length} anchors, '
        'rms ${proj.rmsResidual.toStringAsFixed(1)} m, '
        'max ${worst.value.toStringAsFixed(1)} m (${worst.key}), '
        '${proj.pxPerMetre.toStringAsFixed(2)} px/m',
      );
    });

    test('anchors land on their drawn spot and round-trip', () {
      for (final n in map.nodes.where(
        (n) => n.hasGeo && n.regionId == GeoProjection.regionId,
      )) {
        final p = proj.toImage(n.lat!, n.lng!);
        expect(
          (p - n.pos).distance / proj.pxPerMetre,
          lessThan(25),
          reason: n.id,
        );
        final (lat, lng) = proj.toGeo(p);
        expect(haversine(lat, lng, n.lat!, n.lng!), lessThan(0.01));
      }
    });

    test('the plan is drawn with north to the right, east down', () {
      expect(proj.imageAngle(0), closeTo(0, 0.2));
      expect(proj.imageAngle(90), closeTo(math.pi / 2, 0.2));
      expect(proj.pxPerMetre, inInclusiveRange(3.5, 5.5));
    });

    test('no projection without enough main-plan anchors', () {
      expect(GeoProjection.of(map), same(proj));
      expect(GeoProjection.of(testOfficialMap()), isNull);
      expect(
        placeFix(testOfficialMap(), const LocationFix(40.765, -111.895, 5)),
        isNull,
      );
    });
  });

  group('placement', () {
    test('a fix inside is on the map, near the closest place', () {
      final p = placeFix(map, const LocationFix(40.76583, -111.89503, 10))!;
      expect(p.offMap, isFalse);
      expect(p.near?.place, 'Badge Pick-Up');
      expect(p.radiusPx, closeTo(10 * proj.pxPerMetre, 0.001));
      expect(p.angle, isNull);
    });

    test('just outside the building is still on the map', () {
      // ~100 m south of the 200 South entrance.
      final p = placeFix(map, const LocationFix(40.7645, -111.8952, 10))!;
      expect(p.metresAway, inInclusiveRange(50, 150));
      expect(p.offMap, isFalse);
    });

    test('far away is off the map with a rounded distance', () {
      final p = placeFix(map, const LocationFix(40.7608, -111.8910, 10))!;
      expect(p.offMap, isTrue);
      expect(p.near, isNull);
      expect(p.awayLabel, matches(RegExp(r'^\d+0 m$')));
      final far = placeFix(map, const LocationFix(40.70, -111.89, 10))!;
      expect(far.awayLabel, endsWith(' km'));
    });
  });

  group('live controller', () {
    late StreamController<LocationFix> fixes;
    late LiveLocationController live;
    var follows = 0;
    var asked = 0;

    setUp(() {
      fixes = StreamController<LocationFix>.broadcast();
      follows = 0;
      asked = 0;
      live = LiveLocationController(
        map: map,
        locate: () async {
          asked++;
          return const LocationFix(40.76583, -111.89503, 10);
        },
        positions: () => fixes.stream,
      )..onFollowFix = () => follows++;
    });

    tearDown(() => fixes.close());

    test('first tap starts the stream and follows', () async {
      await live.locateMe();
      expect(asked, 1);
      expect(live.status, LiveStatus.live);
      expect(live.follow, isTrue);
      expect(fixes.hasListener, isTrue);
      expect(follows, 1);
      fixes.add(const LocationFix(40.76635, -111.89503, 10));
      await Future<void>.delayed(Duration.zero);
      expect(follows, 2);
      live.dispose();
    });

    test('panning stops following; tapping again re-centres', () async {
      await live.locateMe();
      live.userMoved();
      expect(live.follow, isFalse);
      fixes.add(const LocationFix(40.76635, -111.89503, 10));
      await Future<void>.delayed(Duration.zero);
      expect(follows, 1);
      expect(live.placement.value!.near!.place, 'Lower Concourse escalator');

      await live.locateMe();
      expect(asked, 1, reason: 'no second permission request');
      expect(live.follow, isTrue);
      expect(follows, 2);
      live.dispose();
    });

    test('off-map fixes do not move the camera', () async {
      await live.locateMe();
      fixes.add(const LocationFix(40.7608, -111.8910, 10));
      await Future<void>.delayed(Duration.zero);
      expect(follows, 1);
      expect(live.placement.value!.offMap, isTrue);
      live.dispose();
    });

    test('pause and dispose stop the stream', () async {
      await live.locateMe();
      live.pause();
      expect(fixes.hasListener, isFalse);
      live.resume();
      expect(fixes.hasListener, isTrue);
      live.dispose();
      expect(fixes.hasListener, isFalse);
    });

    test('denied permission reports why and does not stream', () async {
      final denied = LiveLocationController(
        map: map,
        locate: () async => const LocationFailure(
          'Location permission was not granted. Pick a start point instead.',
        ),
        positions: () => fixes.stream,
      );
      await denied.locateMe();
      expect(denied.status, LiveStatus.unavailable);
      expect(denied.error, 'Location permission was not granted.');
      expect(denied.follow, isFalse);
      expect(fixes.hasListener, isFalse);
      denied.dispose();
      live.dispose();
    });

    test('startStream shows the dot without asking', () async {
      live.startStream(const LocationFix(40.76583, -111.89503, 10));
      expect(asked, 0);
      expect(live.follow, isFalse);
      expect(follows, 0);
      expect(live.placement.value, isNotNull);
      expect(fixes.hasListener, isTrue);
      live.dispose();
      expect(fixes.hasListener, isFalse);
    });
  });
}
