import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'outdoor_map.dart';
import 'outdoor_route.dart';

enum OutdoorStepKind { depart, turn, cross, arrive }

enum TurnDirection {
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
}

/// One card of outdoor turn-by-turn directions.
class OutdoorStep {
  const OutdoorStep({
    required this.kind,
    required this.title,
    required this.points,
    required this.startAlong,
    required this.endAlong,
    this.turn = TurnDirection.straight,
    this.hint,
  });

  final OutdoorStepKind kind;
  final TurnDirection turn;
  final String title;
  final String? hint;

  /// World polyline of this step (a single point for arrival).
  final List<Offset> points;

  /// Where this step starts and ends, in metres along the route.
  final double startAlong, endAlong;

  double get metres => endAlong - startAlong;
  Offset get end => points.last;

  /// "120 m · 2 min" for walking steps.
  String? get distanceLabel => kind == OutdoorStepKind.arrive
      ? null
      : kind == OutdoorStepKind.cross
      ? formatMetres(metres)
      : '${formatMetres(metres)} · ${walkMinutes(metres)} min';
}

/// Compass bearing in degrees (0 = north, 90 = east) from [a] to [b] in
/// world coordinates (y grows south).
double bearing(Offset a, Offset b) {
  final d = b - a;
  return (math.atan2(d.dx, -d.dy) * 180 / math.pi + 360) % 360;
}

/// Signed turn from bearing [from] to [to], -180..180 (positive = right).
double turnAngle(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  return d;
}

const _compass = [
  'north',
  'northeast',
  'east',
  'southeast',
  'south',
  'southwest',
  'west',
  'northwest',
];

String compassName(double bearing) =>
    _compass[((bearing % 360) / 45).round() % 8];

TurnDirection turnDirection(double angle) {
  final a = angle.abs();
  final right = angle > 0;
  if (a < 20) return TurnDirection.straight;
  if (a < 50) {
    return right ? TurnDirection.slightRight : TurnDirection.slightLeft;
  }
  if (a < 140) return right ? TurnDirection.right : TurnDirection.left;
  return right ? TurnDirection.sharpRight : TurnDirection.sharpLeft;
}

class _Group {
  _Group(this.name, this.crossing, this.from, this.to);
  final String? name;
  final bool crossing;
  double from, to;
  double get metres => to - from;
}

/// Turns a route into merged, human-readable steps.
class OutdoorStepBuilder {
  OutdoorStepBuilder(this.map);
  final OutdoorMap map;

  /// [startHint] is shown under the first step (e.g. "Exit through the 200
  /// South entrance"). [destination] is the venue point used for the
  /// left/right side on arrival.
  List<OutdoorStep> build(
    OutdoorRoute route, {
    required String destinationName,
    Offset? destination,
    String? startHint,
  }) {
    final groups = _groups(route);
    final steps = <OutdoorStep>[];
    String? lastNamed;
    double? walkBearing;
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final pts = route.slice(g.from, g.to);
      final inBearing = _entryBearing(route, g);
      if (i == 0) {
        final dir = compassName(inBearing);
        steps.add(
          OutdoorStep(
            kind: OutdoorStepKind.depart,
            title: g.crossing
                ? (g.name == null ? 'Cross the street' : 'Cross ${g.name}')
                : g.name == null
                ? 'Head $dir'
                : 'Head $dir on ${g.name}',
            hint: startHint,
            points: pts,
            startAlong: g.from,
            endAlong: g.to,
          ),
        );
      } else if (g.crossing) {
        steps.add(
          OutdoorStep(
            kind: OutdoorStepKind.cross,
            title: g.name == null ? 'Cross the street' : 'Cross ${g.name}',
            points: pts,
            startAlong: g.from,
            endAlong: g.to,
          ),
        );
      } else {
        // After a crossing, turn relative to the walk before it, so crossing
        // a side street and walking on counts as straight on.
        final outBearing = walkBearing ?? _exitBearing(route, groups[i - 1]);
        final turn = turnDirection(turnAngle(outBearing, inBearing));
        final verb = switch (turn) {
          TurnDirection.straight => 'Continue',
          TurnDirection.slightLeft => 'Bear left',
          TurnDirection.slightRight => 'Bear right',
          TurnDirection.left => 'Turn left',
          TurnDirection.right => 'Turn right',
          TurnDirection.sharpLeft => 'Turn sharp left',
          TurnDirection.sharpRight => 'Turn sharp right',
        };
        final String title;
        if (g.name == null) {
          title = turn == TurnDirection.straight ? 'Continue straight' : verb;
        } else if (turn == TurnDirection.straight && g.name == lastNamed) {
          title = 'Continue on ${g.name}';
        } else {
          title = '$verb onto ${g.name}';
        }
        steps.add(
          OutdoorStep(
            kind: OutdoorStepKind.turn,
            turn: turn,
            title: title,
            points: pts,
            startAlong: g.from,
            endAlong: g.to,
          ),
        );
      }
      if (!g.crossing) {
        if (g.name != null) lastNamed = g.name;
        walkBearing = _exitBearing(route, g);
      }
    }

    // Arrival, with the side from the last heading.
    var side = '';
    final dest = destination;
    if (dest != null && route.metres > 1) {
      final heading = groups.isEmpty
          ? bearing(route.start, route.end)
          : _exitBearing(route, groups.last);
      if ((dest - route.end).distance > 4) {
        final rel = turnAngle(heading, bearing(route.end, dest));
        if (rel.abs() >= 30 && rel.abs() <= 150) {
          side = rel > 0 ? ' on your right' : ' on your left';
        }
      }
    }
    steps.add(
      OutdoorStep(
        kind: OutdoorStepKind.arrive,
        title: 'Arrive at $destinationName$side',
        hint: steps.isEmpty ? startHint : null,
        points: [route.end],
        startAlong: route.metres,
        endAlong: route.metres,
      ),
    );
    return steps;
  }

  /// Heading at the start of a group, over its first ~30 m but skipping
  /// the rounded corner it starts with.
  double _entryBearing(OutdoorRoute r, _Group g) {
    final inset = math.min(5.0, g.metres * 0.2);
    return _bearingBetween(r, g.from + inset, math.min(g.to, g.from + 30), g);
  }

  /// Heading at the end of a group, over its last ~30 m.
  double _exitBearing(OutdoorRoute r, _Group g) {
    final inset = math.min(5.0, g.metres * 0.2);
    return _bearingBetween(r, math.max(g.from, g.to - 30), g.to - inset, g);
  }

  double _bearingBetween(OutdoorRoute r, double from, double to, _Group g) {
    final a = r.pointAt(from), b = r.pointAt(to);
    if ((b - a).distance > 0.5) return bearing(a, b);
    final c = r.pointAt(g.from), d = r.pointAt(g.to);
    if ((d - c).distance > 0.5) return bearing(c, d);
    return bearing(r.start, r.end);
  }

  List<_Group> _groups(OutdoorRoute route) {
    var groups = <_Group>[];
    for (var i = 0; i < route.legs.length; i++) {
      final l = route.legs[i];
      var crossing = l.kind == OutdoorEdgeKind.crossing;
      String? name = crossing ? _crossedName(l) : null;
      // A short crossing that cuts no named street is a driveway or an
      // alley (OSM often names those crosswalks after the road alongside).
      if (crossing && _streetAcross(l) == null && l.metres < 15) {
        crossing = false;
      }
      if (!crossing) name = _walkName(l);
      final from = route.legStart(i), to = from + l.metres;
      if (groups.isNotEmpty &&
          groups.last.crossing == crossing &&
          groups.last.name == name) {
        groups.last.to = to;
      } else {
        groups.add(_Group(name, crossing, from, to));
      }
    }

    // Fold short connectors (corner pieces, refuge islands) and zig-zags
    // into their neighbours, one at a time, re-merging neighbours that end
    // up with the same name.
    var folding = true;
    while (folding && groups.length > 1) {
      folding = false;
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        if (g.crossing) continue;
        final prev = i > 0 ? groups[i - 1] : null;
        final next = i + 1 < groups.length ? groups[i + 1] : null;
        final sandwiched =
            prev != null &&
            next != null &&
            !prev.crossing &&
            !next.crossing &&
            prev.name == next.name &&
            g.metres < (g.name == null ? 40 : 25);
        if (!sandwiched && g.metres >= 15) continue;
        if (prev != null && !prev.crossing) {
          prev.to = g.to;
        } else if (next != null && !next.crossing) {
          next.from = g.from;
        } else if (prev != null) {
          prev.to = g.to;
        } else {
          next!.from = g.from;
        }
        groups.removeAt(i);
        folding = true;
        break;
      }
      final merged = <_Group>[];
      for (final g in groups) {
        if (merged.isNotEmpty &&
            merged.last.crossing == g.crossing &&
            merged.last.name == g.name) {
          merged.last.to = g.to;
        } else {
          merged.add(g);
        }
      }
      groups = merged;
    }
    return groups;
  }

  /// Leg name, or the parallel street for an unnamed sidewalk.
  String? _walkName(RouteLeg l) {
    final own = map.nameOf(l.name);
    if (own != null) return own;
    if (l.metres < 1) return null;
    final mid = (l.a + l.b) / 2;
    final b = bearing(l.a, l.b);
    String? best;
    var bestD = 25.0;
    for (final e in map.edges) {
      if (e.kind != OutdoorEdgeKind.street) continue;
      final name = map.nameOf(e.name);
      if (name == null) continue;
      final a = map.nodes[e.a], c = map.nodes[e.b];
      final rel = turnAngle(b, bearing(a, c)).abs();
      if (rel > 25 && rel < 155) continue;
      final (d, t) = segmentDistance(mid, a, c);
      if (t <= 0 || t >= 1) continue;
      if (d < bestD) {
        bestD = d;
        best = name;
      }
    }
    return best;
  }

  /// The street a crossing leg crosses: from the geometry when a named
  /// street runs across it, else the crossing's own name.
  String? _crossedName(RouteLeg l) => _streetAcross(l) ?? map.nameOf(l.name);

  /// The named street whose centreline this crossing leg actually cuts
  /// (with 3 m of slack at both ends, as crosswalks are often split at the
  /// centreline and streets often end at the junction). A path that only runs near a street, such as a crosswalk
  /// over a driveway next to the road, does not count.
  String? _streetAcross(RouteLeg l) {
    if (l.metres < 1) return null;
    final b = bearing(l.a, l.b);
    final dir = (l.b - l.a) / l.metres;
    final a0 = l.a - dir * 3, b0 = l.b + dir * 3;
    String? best;
    var bestD = double.infinity;
    final mid = (l.a + l.b) / 2;
    for (final e in map.edges) {
      if (e.kind != OutdoorEdgeKind.street) continue;
      final name = map.nameOf(e.name);
      if (name == null) continue;
      final a = map.nodes[e.a], c = map.nodes[e.b];
      if ((c - a).distance < 0.5) continue;
      final rel = turnAngle(b, bearing(a, c)).abs();
      if (rel < 45 || rel > 135) continue;
      final along = (c - a) / (c - a).distance;
      if (!_segmentsCross(a0, b0, a - along * 3, c + along * 3)) continue;
      final (d, _) = segmentDistance(mid, a, c);
      if (d < bestD) {
        bestD = d;
        best = name;
      }
    }
    return best;
  }

  static double _side(Offset p, Offset a, Offset b) =>
      (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);

  static bool _segmentsCross(Offset p1, Offset p2, Offset q1, Offset q2) {
    final d1 = _side(p1, q1, q2), d2 = _side(p2, q1, q2);
    final d3 = _side(q1, p1, p2), d4 = _side(q2, p1, p2);
    return (d1 <= 0) != (d2 <= 0) && (d3 <= 0) != (d4 <= 0);
  }
}
