import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/official_map.dart';
import 'package:kubecon_companion/location/start_point.dart';

Object? _json(String path) => jsonDecode(File(path).readAsStringSync());

void main() {
  final map = OfficialMap.fromJson(
    _json('assets/data/official_map.json')! as Map<String, dynamic>,
  );

  group('geo calibration', () {
    test('the bundled map has a footprint and street entrances', () {
      expect(map.footprint.length, greaterThanOrEqualTo(3));
      final street = groundAnchors(map).where((n) => n.street).map((n) => n.id);
      expect(
        street,
        containsAll([
          OfficialMap.mainEntranceId,
          OfficialMap.westTempleEntranceId,
          OfficialMap.hyattLobbyId,
        ]),
      );
      expect(groundAnchors(map).length, greaterThanOrEqualTo(10));
    });

    test('every ground anchor lies on the building footprint', () {
      for (final n in groundAnchors(map)) {
        expect(
          distanceToFootprint(map, n.lat!, n.lng!),
          lessThan(5),
          reason: n.id,
        );
        expect(n.place, isNotNull, reason: n.id);
      }
    });

    test('every geo anchor can reach every session room', () {
      final venue = Venue.fromJson(_json('assets/data/venue.json'));
      final schedule = ScheduleData.fromJson(
        _json('assets/data/sessions.json'),
      );
      final doors = <String>{
        for (final s in schedule.sessions)
          if (venue.room(s.roomId) case final room?)
            ?map.doorFor(room.id, partOf: room.partOf)?.id,
      };
      expect(doors, isNotEmpty);
      final planner = RoutePlanner(map);
      for (final a in map.nodes.where((n) => n.hasGeo)) {
        for (final d in doors) {
          expect(
            planner.shortestPath(a.id, d),
            isNotNull,
            reason: '${a.id} -> $d',
          );
        }
      }
    });
  });

  group('chooseGeoStart', () {
    test('inside the building snaps to the nearest ground-level anchor', () {
      final nf = map.node('l1-nf-esc')!;
      final g = chooseGeoStart(
        map,
        lat: nf.lat! + 0.00002,
        lng: nf.lng!,
        accuracy: 25,
      );
      expect(g.kind, GeoStartKind.indoor);
      expect(g.node.id, 'l1-nf-esc');
      expect(g.placeName, 'North Foyer escalators');
    });

    test('a fix on the sidewalk next to the building counts as indoors', () {
      // West Temple sidewalk, ~40 m east of the West Temple entrance.
      final g = chooseGeoStart(map, lat: 40.7672, lng: -111.8938, accuracy: 30);
      expect(g.kind, GeoStartKind.indoor);
      expect(g.node.id, OfficialMap.westTempleEntranceId);
    });

    test('never picks an upper-level anchor', () {
      final l2 = map.node('sp-l2-east-entrance')!;
      expect(l2.hasGeo, isTrue);
      final g = chooseGeoStart(map, lat: l2.lat, lng: l2.lng, accuracy: 10);
      expect(map.floorOf(g.node.regionId), 1);
    });

    test('near the venue walks outside to the closest street entrance', () {
      // About 450 m south, on West Temple past 300 South.
      final g = chooseGeoStart(map, lat: 40.7614, lng: -111.8940, accuracy: 20);
      expect(g.kind, GeoStartKind.nearby);
      expect(g.node.street, isTrue);
      expect(
        g.node.id,
        isIn([OfficialMap.mainEntranceId, OfficialMap.hyattLobbyId]),
      );
      expect(g.outdoorMetres, inInclusiveRange(400, 600));
      expect(g.outdoorMinutes, inInclusiveRange(6, 8));
      expect(walkingDirectionsUrl(g.node), contains('travelmode=walking'));
      expect(walkingDirectionsUrl(g.node), isNot(contains('origin')));
    });

    test('north of the venue walks to the West Temple entrance', () {
      // Temple Square side, South Temple and West Temple.
      final g = chooseGeoStart(map, lat: 40.7694, lng: -111.8939, accuracy: 20);
      expect(g.kind, GeoStartKind.nearby);
      expect(g.node.id, OfficialMap.westTempleEntranceId);
    });

    test('far away falls back to the 200 South entrance', () {
      // Salt Lake City airport, ~8 km away.
      final g = chooseGeoStart(map, lat: 40.7899, lng: -111.9791, accuracy: 10);
      expect(g.kind, GeoStartKind.fallback);
      expect(g.reason, GeoFallbackReason.tooFar);
      expect(g.node.id, OfficialMap.mainEntranceId);
    });

    test('poor accuracy falls back to the 200 South entrance', () {
      final nf = map.node('l1-nf-esc')!;
      final g = chooseGeoStart(map, lat: nf.lat, lng: nf.lng, accuracy: 400);
      expect(g.kind, GeoStartKind.fallback);
      expect(g.reason, GeoFallbackReason.inaccurate);
      expect(g.node.id, OfficialMap.mainEntranceId);
    });

    test('denied or unavailable location falls back to 200 South', () {
      final g = chooseGeoStart(map);
      expect(g.kind, GeoStartKind.fallback);
      expect(g.reason, GeoFallbackReason.unavailable);
      expect(g.node.id, OfficialMap.mainEntranceId);
    });
  });

  group('walk label', () {
    MapRoute route(double metres, {int changes = 0}) => MapRoute(
      nodeIds: const [],
      steps: const [],
      walkMetres: metres,
      levelChanges: changes,
    );

    test('has no tilde and handles very short walks', () {
      expect(route(20).walkLabel, '<1 min walk');
      expect(route(300).walkLabel, '4 min walk');
      expect(route(150, changes: 1).walkLabel, '3 min walk');
    });
  });
}
