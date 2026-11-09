import 'dart:ui' show Offset;

import 'outdoor_map.dart';
import 'outdoor_route.dart';
import 'outdoor_steps.dart';

/// Thresholds for outdoor start selection and live guidance.
class OutdoorNavRules {
  const OutdoorNavRules._();

  /// Fixes further than this from the map area are not used.
  static const maxDistanceMetres = 3000.0;

  /// Fixes less precise than this are not used.
  static const maxAccuracyMetres = 150.0;

  /// Fixes this close to a venue building count as "at the venue".
  static const venueMetres = 60.0;

  /// Advance to the next step this close to the end of the current one.
  static const advanceMetres = 15.0;

  /// Further than this from the route counts as off route...
  static const offRouteMetres = 40.0;

  /// ...for this many fixes in a row before rerouting.
  static const offRouteFixes = 2;

  /// This close to the destination counts as arrived.
  static const arriveMetres = 20.0;
}

enum OutdoorStartKind {
  /// From the user's position (snapped to the nearest path).
  gps,

  /// The user is at the venue: from the exit closest to the destination.
  atVenue,

  /// An exit picked by hand.
  picked,

  /// No usable fix: the exit closest to the destination.
  fallback,
}

enum OutdoorFallbackReason { unavailable, inaccurate, tooFar }

/// Where an outdoor route starts.
class OutdoorStart {
  const OutdoorStart({
    required this.kind,
    required this.point,
    this.exit,
    this.reason,
  });

  final OutdoorStartKind kind;
  final GraphPoint point;
  final VenueExit? exit;
  final OutdoorFallbackReason? reason;

  bool get fromGps => kind == OutdoorStartKind.gps;

  /// "From your location", "From the 200 South entrance".
  String get label =>
      exit == null ? 'From your location' : 'From ${theExit(exit!.label)}';

  /// Shown under the first step.
  String? get hint =>
      exit == null ? null : 'Leave the venue through ${theExit(exit!.label)}';
}

/// "the 200 South entrance" (no double article).
String theExit(String label) =>
    label.toLowerCase().startsWith('the ') ? label : 'the $label';

/// The destination of an off-site venue on the outdoor map.
class OutdoorTarget {
  const OutdoorTarget({
    required this.point,
    required this.venuePos,
    required this.name,
    this.building,
  });

  /// Where routes end (on the walking graph).
  final GraphPoint point;

  /// The venue itself (used for left/right on arrival).
  final Offset venuePos;
  final String name;
  final OutdoorBuilding? building;
}

/// Resolves an off-site venue to a routable target, or null when the map
/// does not cover it.
OutdoorTarget? resolveTarget(
  OutdoorMap map, {
  required String id,
  required String name,
  String? fullName,
  double? lat,
  double? lng,
}) {
  final d = map.destinations[id];
  GraphPoint? point;
  Offset? venue;
  if (d != null && d.node >= 0 && d.node < map.nodes.length) {
    point = map.nodePoint(d.node);
    venue = map.project(d.lat, d.lng);
  } else if (lat != null &&
      lng != null &&
      map.projection.distanceToBox(lat, lng) == 0) {
    venue = map.project(lat, lng);
    point = map.snap(venue);
  }
  if (point == null || venue == null) return null;
  // The venue's footprint: same name first, else the nearest one close by.
  OutdoorBuilding? building;
  var best = 30.0;
  for (final b in map.buildings) {
    if (b.kind != OutdoorBuildingKind.destination) continue;
    if (b.name == name || b.name == fullName) {
      building = b;
      break;
    }
    final dist = b.distanceTo(venue);
    if (dist < best) {
      best = dist;
      building = b;
    }
  }
  return OutdoorTarget(
    point: point,
    venuePos: venue,
    name: name,
    building: building,
  );
}

/// The venue exit with the shortest walk to [target].
VenueExit? bestExit(OutdoorMap map, GraphPoint target) {
  if (map.exits.isEmpty) return null;
  final costs = OutdoorRouter(map).costsFrom(target);
  VenueExit? best;
  var bestCost = double.infinity;
  for (final x in map.exits) {
    final c = costs[x.node];
    if (c < bestCost) {
      bestCost = c;
      best = x;
    }
  }
  return best ?? map.exits.first;
}

/// Picks the start for a route to [target] from a GPS fix (all null when
/// there is none) or a hand-picked exit.
OutdoorStart chooseOutdoorStart(
  OutdoorMap map,
  GraphPoint target, {
  double? lat,
  double? lng,
  double? accuracy,
  String? exitId,
}) {
  final picked = exitId == null ? null : map.exit(exitId);
  if (picked != null) {
    return OutdoorStart(
      kind: OutdoorStartKind.picked,
      point: map.nodePoint(picked.node),
      exit: picked,
    );
  }
  final exit = bestExit(map, target);
  OutdoorStart fromExit(OutdoorStartKind kind, [OutdoorFallbackReason? r]) =>
      OutdoorStart(
        kind: kind,
        point: exit == null ? target : map.nodePoint(exit.node),
        exit: exit,
        reason: r,
      );

  if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
    return fromExit(
      OutdoorStartKind.fallback,
      OutdoorFallbackReason.unavailable,
    );
  }
  if (accuracy == null ||
      !accuracy.isFinite ||
      accuracy > OutdoorNavRules.maxAccuracyMetres) {
    return fromExit(
      OutdoorStartKind.fallback,
      OutdoorFallbackReason.inaccurate,
    );
  }
  if (map.projection.distanceToBox(lat, lng) >
      OutdoorNavRules.maxDistanceMetres) {
    return fromExit(OutdoorStartKind.fallback, OutdoorFallbackReason.tooFar);
  }
  final pos = map.project(lat, lng);
  if (map.distanceToVenue(pos) <= OutdoorNavRules.venueMetres) {
    return fromExit(OutdoorStartKind.atVenue);
  }
  final snapped = map.snap(pos);
  if (snapped == null) {
    return fromExit(
      OutdoorStartKind.fallback,
      OutdoorFallbackReason.unavailable,
    );
  }
  return OutdoorStart(kind: OutdoorStartKind.gps, point: snapped);
}

/// A planned walk: route plus steps.
class OutdoorPlan {
  const OutdoorPlan(this.start, this.route, this.steps);
  final OutdoorStart start;
  final OutdoorRoute route;
  final List<OutdoorStep> steps;
}

/// Routes from [start] to [target] and builds the steps; null when
/// unreachable.
OutdoorPlan? planWalk(
  OutdoorMap map,
  OutdoorStart start,
  OutdoorTarget target,
) {
  final route = OutdoorRouter(map).route(start.point, target.point);
  if (route == null) return null;
  final steps = OutdoorStepBuilder(map).build(
    route,
    destinationName: target.name,
    destination: target.venuePos,
    startHint: start.hint,
  );
  return OutdoorPlan(start, route, steps);
}

enum NavEvent { none, advanced, reroute, arrived }

/// Follows live fixes along a plan: auto-advance, off-route detection and
/// arrival. Pure logic; the screen acts on the returned events.
class NavTracker {
  NavTracker(this.route, this.steps, {this.step = 0});

  final OutdoorRoute route;
  final List<OutdoorStep> steps;

  /// Current step index.
  int step;
  int _offRoute = 0;
  bool arrived = false;

  int get _lastWalk => steps.length - 2;

  NavEvent update(Offset pos, double accuracy) {
    if (arrived) return NavEvent.none;
    if ((pos - route.end).distance <= OutdoorNavRules.arriveMetres) {
      arrived = true;
      step = steps.length - 1;
      return NavEvent.arrived;
    }
    if (!accuracy.isFinite || accuracy > OutdoorNavRules.maxAccuracyMetres) {
      return NavEvent.none;
    }
    final (dist, along) = route.nearest(pos);
    if (dist > OutdoorNavRules.offRouteMetres) {
      _offRoute++;
      if (_offRoute >= OutdoorNavRules.offRouteFixes) {
        _offRoute = 0;
        return NavEvent.reroute;
      }
      return NavEvent.none;
    }
    _offRoute = 0;

    final before = step;
    while (step <= _lastWalk) {
      final st = steps[step];
      final nearEnd = (pos - st.end).distance <= OutdoorNavRules.advanceMetres;
      final past = along > st.endAlong + OutdoorNavRules.advanceMetres;
      if (!nearEnd && !past) break;
      step++;
      // Only one step per fix when merely near the end.
      if (!past) break;
    }
    return step != before ? NavEvent.advanced : NavEvent.none;
  }
}
