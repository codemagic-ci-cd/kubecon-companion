import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// Equirectangular projection to local metres around the centre of a
/// bounding box. World coordinates have their origin at the north-west
/// corner, x grows east and y grows south (canvas orientation), so they can
/// be painted directly.
class GeoProjection {
  GeoProjection(this.minLat, this.minLng, this.maxLat, this.maxLng)
    : _kLat = math.pi / 180 * _earth,
      _kLng =
          math.pi /
          180 *
          _earth *
          math.cos((minLat + maxLat) / 2 * math.pi / 180);

  static const _earth = 6371000.0;

  final double minLat, minLng, maxLat, maxLng;
  final double _kLat, _kLng;

  /// World size in metres.
  Size get size => Size((maxLng - minLng) * _kLng, (maxLat - minLat) * _kLat);

  Offset project(double lat, double lng) =>
      Offset((lng - minLng) * _kLng, (maxLat - lat) * _kLat);

  /// Metres from a point to the bounding box (0 inside it).
  double distanceToBox(double lat, double lng) {
    final p = project(lat, lng);
    final s = size;
    final dx = p.dx < 0 ? -p.dx : (p.dx > s.width ? p.dx - s.width : 0.0);
    final dy = p.dy < 0 ? -p.dy : (p.dy > s.height ? p.dy - s.height : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }
}

enum OutdoorEdgeKind { street, footway, crossing, steps }

class OutdoorEdge {
  const OutdoorEdge(this.a, this.b, this.name, this.kind, this.metres);
  final int a, b;

  /// Index into [OutdoorMap.names], or -1 when unnamed.
  final int name;
  final OutdoorEdgeKind kind;
  final double metres;

  /// Routing cost (same weights as tool/build_outdoor.py KIND_COST).
  /// Downtown sidewalks are mapped as separate footways, so road
  /// centrelines cost three times as much: routes follow sidewalks and
  /// crosswalks and only use a road where no footway exists. Steps are a
  /// little slower than flat ground.
  double get cost => switch (kind) {
    OutdoorEdgeKind.street => metres * 3,
    OutdoorEdgeKind.steps => metres * 1.2,
    _ => metres,
  };

  int other(int n) => n == a ? b : a;
}

class StreetLabel {
  const StreetLabel(this.name, this.pos, this.angle);
  final String name;
  final Offset pos;

  /// Degrees as given in the data (only a fallback; the painter aligns
  /// labels with the street geometry).
  final double angle;
}

enum OutdoorBuildingKind { venue, destination, landmark }

class OutdoorBuilding {
  OutdoorBuilding(this.name, this.kind, this.outline);
  final String name;
  final OutdoorBuildingKind kind;
  final List<Offset> outline;

  late final Offset centroid = outline.isEmpty
      ? Offset.zero
      : outline.reduce((a, b) => a + b) / outline.length.toDouble();

  bool contains(Offset p) => pointInPolygon(p, outline);

  /// Metres from [p] to the outline; 0 inside.
  double distanceTo(Offset p) {
    if (outline.length < 3) return (p - centroid).distance;
    if (contains(p)) return 0;
    var best = double.infinity;
    for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
      best = math.min(best, segmentDistance(p, outline[j], outline[i]).$1);
    }
    return best;
  }
}

/// A Salt Palace entrance on the street, linked to a street node.
class VenueExit {
  const VenueExit(this.id, this.label, this.lat, this.lng, this.node, this.pos);
  final String id;
  final String label;
  final double lat, lng;
  final int node;
  final Offset pos;
}

class OutdoorDestination {
  const OutdoorDestination(this.node, this.lat, this.lng);
  final int node;
  final double lat, lng;
}

/// A point on the walking graph: a node, or a spot along an edge.
class GraphPoint {
  const GraphPoint.node(this.node, this.pos) : edge = null, t = 0;
  const GraphPoint.onEdge(this.edge, this.t, this.pos) : node = null;
  final int? node;
  final int? edge;

  /// 0 at the edge's `a`, 1 at its `b`.
  final double t;
  final Offset pos;
}

/// Street graph and base map for walking to off-site venues
/// (assets/data/outdoor.json, from OpenStreetMap).
class OutdoorMap {
  OutdoorMap._({
    required this.attribution,
    required this.projection,
    required this.nodes,
    required this.edges,
    required this.names,
    required this.labels,
    required this.buildings,
    required this.exits,
    required this.destinations,
  }) {
    adjacency = List.generate(nodes.length, (_) => <int>[]);
    for (var i = 0; i < edges.length; i++) {
      adjacency[edges[i].a].add(i);
      adjacency[edges[i].b].add(i);
    }
  }

  factory OutdoorMap.fromJson(Map<String, dynamic> j) {
    final box = (j['bbox'] as List).map((e) => (e as num).toDouble()).toList();
    final proj = GeoProjection(box[0], box[1], box[2], box[3]);
    Offset ll(Object? p) {
      final l = p as List;
      return proj.project((l[0] as num).toDouble(), (l[1] as num).toDouble());
    }

    final nodes = [for (final n in (j['nodes'] as List? ?? const [])) ll(n)];
    final edges = <OutdoorEdge>[];
    for (final e in (j['edges'] as List? ?? const [])) {
      final l = e as List;
      final a = (l[0] as num).toInt(), b = (l[1] as num).toInt();
      if (a < 0 || b < 0 || a >= nodes.length || b >= nodes.length) continue;
      if (a == b) continue;
      final name = l.length > 2 && l[2] is num ? (l[2] as num).toInt() : -1;
      final k = l.length > 3 && l[3] is num ? (l[3] as num).toInt() : 0;
      edges.add(
        OutdoorEdge(
          a,
          b,
          name,
          OutdoorEdgeKind.values[k.clamp(0, 3)],
          (nodes[a] - nodes[b]).distance,
        ),
      );
    }
    final names = [
      for (final n in (j['names'] as List? ?? const [])) n.toString(),
    ];
    double d(Object? v) => (v as num).toDouble();
    return OutdoorMap._(
      attribution:
          (j['attribution'] as String?) ?? '© OpenStreetMap contributors',
      projection: proj,
      nodes: nodes,
      edges: edges,
      names: names,
      labels: [
        for (final l in (j['labels'] as List? ?? const []))
          if (l is Map)
            StreetLabel(
              l['name'].toString(),
              proj.project(d(l['lat']), d(l['lng'])),
              l['angle'] is num ? d(l['angle']) : 0,
            ),
      ],
      buildings: [
        for (final b in (j['buildings'] as List? ?? const []))
          if (b is Map)
            OutdoorBuilding(
              (b['name'] ?? '').toString(),
              switch (b['kind']) {
                'venue' => OutdoorBuildingKind.venue,
                'destination' => OutdoorBuildingKind.destination,
                _ => OutdoorBuildingKind.landmark,
              },
              [for (final p in (b['outline'] as List? ?? const [])) ll(p)],
            ),
      ],
      exits: [
        for (final x in (j['venueExits'] as List? ?? const []))
          if (x is Map &&
              x['node'] is num &&
              (x['node'] as num).toInt() < nodes.length)
            VenueExit(
              x['id'].toString(),
              (x['label'] ?? x['id']).toString(),
              d(x['lat']),
              d(x['lng']),
              (x['node'] as num).toInt(),
              proj.project(d(x['lat']), d(x['lng'])),
            ),
      ],
      destinations: {
        for (final e in ((j['destinations'] as Map?) ?? const {}).entries)
          if (e.value is Map && (e.value['node'] as num?) != null)
            e.key.toString(): OutdoorDestination(
              (e.value['node'] as num).toInt(),
              d(e.value['lat']),
              d(e.value['lng']),
            ),
      },
    );
  }

  final String attribution;
  final GeoProjection projection;

  /// World positions (metres) by node id.
  final List<Offset> nodes;
  final List<OutdoorEdge> edges;
  final List<String> names;
  final List<StreetLabel> labels;
  final List<OutdoorBuilding> buildings;
  final List<VenueExit> exits;
  final Map<String, OutdoorDestination> destinations;

  /// Edge indices by node.
  late final List<List<int>> adjacency;

  Size get size => projection.size;
  Rect get bounds => Offset.zero & size;

  Offset project(double lat, double lng) => projection.project(lat, lng);

  String? nameOf(int i) => i >= 0 && i < names.length ? names[i] : null;

  VenueExit? exit(String id) {
    for (final x in exits) {
      if (x.id == id) return x;
    }
    return null;
  }

  /// Nearest point on any edge (not just nodes) to [p].
  GraphPoint? snap(Offset p, {bool Function(OutdoorEdge e)? where}) {
    GraphPoint? best;
    var bestD = double.infinity;
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      if (where != null && !where(e)) continue;
      final (dist, t) = segmentDistance(p, nodes[e.a], nodes[e.b]);
      if (dist < bestD) {
        bestD = dist;
        if (t <= 0) {
          best = GraphPoint.node(e.a, nodes[e.a]);
        } else if (t >= 1) {
          best = GraphPoint.node(e.b, nodes[e.b]);
        } else {
          best = GraphPoint.onEdge(
            i,
            t,
            Offset.lerp(nodes[e.a], nodes[e.b], t)!,
          );
        }
      }
    }
    return best;
  }

  GraphPoint nodePoint(int n) => GraphPoint.node(n, nodes[n]);

  /// Distance from [p] to the nearest venue building (or exit when the data
  /// has no venue outline).
  double distanceToVenue(Offset p) {
    var best = double.infinity;
    var any = false;
    for (final b in buildings) {
      if (b.kind != OutdoorBuildingKind.venue) continue;
      any = true;
      best = math.min(best, b.distanceTo(p));
    }
    if (!any) {
      for (final x in exits) {
        best = math.min(best, (x.pos - p).distance);
      }
    }
    return best;
  }
}

/// Distance from [p] to segment [a]-[b] and the projection parameter t.
(double, double) segmentDistance(Offset p, Offset a, Offset b) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  final t = len2 == 0
      ? 0.0
      : (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / len2).clamp(0.0, 1.0);
  final q = a + d * t;
  return ((p - q).distance, t);
}

bool pointInPolygon(Offset p, List<Offset> poly) {
  if (poly.length < 3) return false;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
