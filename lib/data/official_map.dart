import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// The official KubeCon venue map image, annotated by us: panels (regions),
/// room boxes and a walking graph, all in image pixel coordinates.
/// Built by tool/merge_official_map.py into assets/data/official_map.json.
class OfficialMap {
  OfficialMap({
    required this.image,
    required this.width,
    required this.height,
    required this.credit,
    required this.sourceUrl,
    required this.regions,
    required this.rooms,
    required this.nodes,
    required this.edges,
    this.footprint = const [],
  }) {
    for (final r in regions) {
      _regions[r.id] = r;
    }
    for (final n in nodes) {
      _nodes[n.id] = n;
      _adj[n.id] = [];
    }
    for (final e in edges) {
      if (!_nodes.containsKey(e.from) || !_nodes.containsKey(e.to)) continue;
      _adj[e.from]!.add(e);
      _adj[e.to]!.add(e);
    }
  }

  final String image;
  final double width;
  final double height;
  final String credit;
  final String sourceUrl;
  final List<MapRegion> regions;
  final Map<String, MapRoom> rooms;
  final List<MapNode> nodes;
  final List<MapEdge> edges;

  /// Building outline (Salt Palace + Hyatt) as (lat, lng) points; empty when
  /// the map has no geo calibration.
  final List<(double, double)> footprint;

  final _regions = <String, MapRegion>{};
  final _nodes = <String, MapNode>{};
  final _adj = <String, List<MapEdge>>{};

  static const mainEntranceId = 'sp-entrance-200-south';
  static const westTempleEntranceId = 'sp-entrance-west-temple';
  static const hyattLobbyId = 'sp-hyatt-lobby-elevators';

  Size2 get size => Size2(width, height);
  Rect get bounds => Rect.fromLTWH(0, 0, width, height);

  MapRegion? region(String? id) => id == null ? null : _regions[id];
  MapNode? node(String? id) => id == null ? null : _nodes[id];
  List<MapEdge> edgesOf(String nodeId) => _adj[nodeId] ?? const [];

  /// Room geometry for a venue room id; falls back to the room it is part of
  /// (e.g. "Regency Ballroom B" lives inside "Regency Ballroom B-D").
  MapRoom? room(String? id, {String? partOf}) {
    if (id != null && rooms[id] != null) return rooms[id];
    if (partOf != null) return rooms[partOf];
    return null;
  }

  /// The door node used to reach a room.
  MapNode? doorFor(String? id, {String? partOf}) =>
      node('door-$id') ?? (partOf == null ? null : node('door-$partOf'));

  /// Smallest room box containing [p] (rooms can be nested).
  String? roomAt(Offset p) {
    String? best;
    var bestArea = double.infinity;
    rooms.forEach((id, r) {
      if (r.rect.contains(p) && r.rect.width * r.rect.height < bestArea) {
        bestArea = r.rect.width * r.rect.height;
        best = id;
      }
    });
    return best;
  }

  /// Floor number for the level of a region ("L2" -> 2, "H4" -> 4).
  int floorOf(String regionId) {
    final lvl = region(regionId)?.levelId ?? regionId;
    final m = RegExp(r'(\d+)').firstMatch(lvl);
    return m == null ? 1 : int.parse(m.group(1)!);
  }

  /// "Level 2" for Salt Palace, "Hyatt Level 4" for the hotel.
  String levelLabel(String regionId) {
    final r = region(regionId);
    final n = floorOf(regionId);
    return r?.isHyatt == true ? 'Hyatt Level $n' : 'Level $n';
  }

  /// Rough metres per image pixel. The map is not to scale, so this is an
  /// estimate: the Salt Palace main plan is taken as ~600 m wide and each
  /// Hyatt panel as ~120 m wide.
  double metresPerPixel(String regionId) {
    final r = region(regionId);
    if (r != null && r.isHyatt) return 120 / r.rect.width;
    final sp = region('sp-L1');
    return sp == null ? 0.3 : 600 / sp.rect.width;
  }

  factory OfficialMap.fromJson(Map<String, dynamic> j) {
    double d(Object? v) => v is num ? v.toDouble() : 0;
    final regions = <MapRegion>[
      for (final r in (j['regions'] as List? ?? const []))
        if (r is Map)
          MapRegion(
            id: '${r['id']}',
            label: '${r['label'] ?? r['id']}',
            building: '${r['building'] ?? ''}',
            levelId: '${r['levelId'] ?? ''}',
            rect: _rect(r['rect']),
          ),
    ];
    final rooms = <String, MapRoom>{};
    final rawRooms = j['rooms'];
    if (rawRooms is Map) {
      rawRooms.forEach((k, v) {
        if (v is! Map) return;
        rooms['$k'] = MapRoom(
          id: '$k',
          rect: Rect.fromLTWH(d(v['x']), d(v['y']), d(v['w']), d(v['h'])),
          regionId: '${v['regionId'] ?? ''}',
          label: v['label'] as String?,
        );
      });
    }
    final nodes = <MapNode>[
      for (final n in (j['nodes'] as List? ?? const []))
        if (n is Map)
          MapNode(
            id: '${n['id']}',
            pos: Offset(d(n['x']), d(n['y'])),
            regionId: '${n['regionId'] ?? ''}',
            kind: '${n['kind'] ?? 'junction'}',
            label: n['label'] as String?,
            lat: (n['lat'] as num?)?.toDouble(),
            lng: (n['lng'] as num?)?.toDouble(),
            place: n['place'] as String?,
            street: n['street'] == true,
          ),
    ];
    final edges = <MapEdge>[
      for (final e in (j['edges'] as List? ?? const []))
        if (e is Map)
          MapEdge(
            from: '${e['from']}',
            to: '${e['to']}',
            kind: _edgeKind('${e['kind'] ?? 'walk'}'),
            hint: e['hint'] as String?,
          ),
    ];
    final geo = j['geo'];
    final footprint = <(double, double)>[
      if (geo is Map)
        for (final p in (geo['footprint'] as List? ?? const []))
          if (p is List && p.length == 2) (d(p[0]), d(p[1])),
    ];
    return OfficialMap(
      image: '${j['image'] ?? 'assets/maps/kcna26_venue_map.jpg'}',
      width: d(j['width']),
      height: d(j['height']),
      credit:
          '${j['credit'] ?? 'Venue map: KubeCon + CloudNativeCon / Linux Foundation'}',
      sourceUrl:
          '${j['sourceUrl'] ?? 'https://events.linuxfoundation.org/kcna26-venue-map'}',
      regions: regions,
      rooms: rooms,
      nodes: nodes,
      edges: edges,
      footprint: footprint,
    );
  }

  static Rect _rect(Object? v) {
    if (v is List && v.length == 4) {
      final n = v.map((e) => (e as num).toDouble()).toList();
      return Rect.fromLTWH(n[0], n[1], n[2], n[3]);
    }
    return Rect.zero;
  }

  static EdgeKind _edgeKind(String k) => switch (k) {
    'escalator' => EdgeKind.escalator,
    'elevator' => EdgeKind.elevator,
    'stairs' => EdgeKind.stairs,
    _ => EdgeKind.walk,
  };
}

class Size2 {
  const Size2(this.width, this.height);
  final double width;
  final double height;
}

class MapRegion {
  const MapRegion({
    required this.id,
    required this.label,
    required this.building,
    required this.levelId,
    required this.rect,
  });
  final String id;
  final String label;
  final String building;
  final String levelId;
  final Rect rect;
  bool get isHyatt => building.toLowerCase().contains('hyatt');
}

class MapRoom {
  const MapRoom({
    required this.id,
    required this.rect,
    required this.regionId,
    this.label,
  });
  final String id;
  final Rect rect;
  final String regionId;
  final String? label;
}

class MapNode {
  const MapNode({
    required this.id,
    required this.pos,
    required this.regionId,
    required this.kind,
    this.label,
    this.lat,
    this.lng,
    this.place,
    this.street = false,
  });
  final String id;
  final Offset pos;
  final String regionId;
  final String kind;
  final String? label;
  final double? lat;
  final double? lng;

  /// Short place name for geo anchors ("North Foyer escalators").
  final String? place;

  /// A door to the street, used as the end of an outdoor walking leg.
  final bool street;

  bool get hasGeo => lat != null && lng != null;
}

enum EdgeKind { walk, escalator, elevator, stairs }

class MapEdge {
  const MapEdge({
    required this.from,
    required this.to,
    required this.kind,
    this.hint,
  });
  final String from;
  final String to;
  final EdgeKind kind;
  final String? hint;
  String other(String id) => id == from ? to : from;
}

// ---------------------------------------------------------------------------
// Routing

enum RouteStepKind { outdoor, walk, escalator, elevator, stairs, arrive }

/// One card in the directions pager.
class RouteStep {
  const RouteStep({
    required this.kind,
    required this.title,
    required this.points,
    required this.regionId,
    this.hint,
    this.metres = 0,
    this.fromRegionId,
    this.mapsUrl,
  });

  final RouteStepKind kind;
  final String title;

  /// Extra landmark hint, e.g. "Pass Badge Pick-Up on your left".
  final String? hint;

  /// Polyline (image px) for this step. Level changes hold [from, to].
  final List<Offset> points;

  /// Region the step ends in (the camera goes here).
  final String regionId;

  /// For level changes: the region you leave.
  final String? fromRegionId;
  final double metres;

  /// For outdoor legs: walking directions in a maps app.
  final String? mapsUrl;

  bool get isLevelChange =>
      kind == RouteStepKind.escalator ||
      kind == RouteStepKind.elevator ||
      kind == RouteStepKind.stairs;
}

class MapRoute {
  const MapRoute({
    required this.nodeIds,
    required this.steps,
    required this.walkMetres,
    required this.levelChanges,
    this.outdoorMetres = 0,
  });
  final List<String> nodeIds;
  final List<RouteStep> steps;
  final double walkMetres;
  final int levelChanges;

  /// Walk outside the building before the first indoor step.
  final double outdoorMetres;

  /// Walking estimate: ~75 m/min plus about a minute per level change.
  double get exactMinutes =>
      (walkMetres + outdoorMetres) / 75 + levelChanges * 1.0;

  int get minutes => math.max(1, exactMinutes.round());

  /// "4 min walk", or "<1 min walk" for very short routes.
  String get walkLabel =>
      exactMinutes < 0.75 ? '<1 min walk' : '$minutes min walk';

  /// This route with an outdoor walk to its first node put in front.
  MapRoute withOutdoorLeg(RouteStep leg) => MapRoute(
    nodeIds: nodeIds,
    steps: [leg, ...steps],
    walkMetres: walkMetres,
    levelChanges: levelChanges,
    outdoorMetres: outdoorMetres + leg.metres,
  );
}

/// Dijkstra over the map graph and turn-by-turn step building.
class RoutePlanner {
  RoutePlanner(this.map);
  final OfficialMap map;

  static const _blocked = 100000.0;

  double _cost(MapEdge e, {required bool stepFree}) {
    final a = map.node(e.from)!, b = map.node(e.to)!;
    switch (e.kind) {
      case EdgeKind.walk:
        if (a.regionId != b.regionId) return 30;
        final mpp = map.metresPerPixel(a.regionId);
        return (a.pos - b.pos).distance * mpp;
      case EdgeKind.escalator:
        return 40 + (stepFree ? _blocked : 0);
      case EdgeKind.stairs:
        return 50 + (stepFree ? _blocked : 0);
      case EdgeKind.elevator:
        // Waiting for a lift costs more unless you need step-free access.
        return stepFree ? 40 : 110;
    }
  }

  /// Shortest node path, or null if unreachable.
  List<String>? shortestPath(String from, String to, {bool stepFree = false}) {
    if (map.node(from) == null || map.node(to) == null) return null;
    final dist = <String, double>{from: 0};
    final prev = <String, String>{};
    final done = <String>{};
    final open = <String>{from};
    while (open.isNotEmpty) {
      String? u;
      var best = double.infinity;
      for (final n in open) {
        final dn = dist[n]!;
        if (dn < best) {
          best = dn;
          u = n;
        }
      }
      open.remove(u);
      if (u == to) break;
      done.add(u!);
      for (final e in map.edgesOf(u)) {
        final v = e.other(u);
        if (done.contains(v)) continue;
        final nd = best + _cost(e, stepFree: stepFree);
        if (nd < (dist[v] ?? double.infinity)) {
          dist[v] = nd;
          prev[v] = u;
          open.add(v);
        }
      }
    }
    if (!dist.containsKey(to)) return null;
    final path = <String>[to];
    while (path.last != from) {
      path.add(prev[path.last]!);
    }
    return path.reversed.toList();
  }

  MapEdge _edge(String a, String b) => map
      .edgesOf(a)
      .firstWhere((e) => e.other(a) == b && (e.from == b || e.to == b));

  /// Plans a route from node [fromNodeId] to the door of a room.
  MapRoute? route({
    required String fromNodeId,
    required String toNodeId,
    String? destinationName,
    Rect? destinationRect,
    String? startName,
    bool stepFree = false,
  }) {
    final path = shortestPath(fromNodeId, toNodeId, stepFree: stepFree);
    if (path == null) return null;
    return _buildSteps(
      path,
      destinationName: destinationName,
      destinationRect: destinationRect,
      startName: startName,
    );
  }

  MapRoute _buildSteps(
    List<String> path, {
    String? destinationName,
    Rect? destinationRect,
    String? startName,
  }) {
    final nodes = path.map((id) => map.node(id)!).toList();
    final edges = [
      for (var i = 1; i < path.length; i++) _edge(path[i - 1], path[i]),
    ];
    // Hints are written for walking an edge from -> to; skip them when the
    // route uses the edge the other way round.
    String? hintAt(int k) {
      final h = edges[k].hint?.trim();
      if (h == null || h.isEmpty || edges[k].from != path[k]) return null;
      return h;
    }

    bool isChange(int i) =>
        edges[i].kind != EdgeKind.walk ||
        nodes[i].regionId != nodes[i + 1].regionId;

    // The last short hop from the corridor into the room door becomes the
    // arrival step.
    final hasApproach =
        edges.isNotEmpty &&
        !isChange(edges.length - 1) &&
        nodes.last.kind == 'door';
    final walkEnd = hasApproach ? edges.length - 1 : edges.length;

    // 1. Raw items: walking runs split at turns, and level changes.
    final items = <Object>[]; // _Walk or RouteStep
    var changes = 0;
    var i = 0;
    while (i < walkEnd) {
      if (isChange(i)) {
        var j = i;
        while (j + 1 < walkEnd &&
            isChange(j + 1) &&
            edges[j + 1].kind == edges[i].kind) {
          j++;
        }
        final from = nodes[i], to = nodes[j + 1];
        final kind = switch (edges[i].kind) {
          EdgeKind.escalator => RouteStepKind.escalator,
          EdgeKind.elevator => RouteStepKind.elevator,
          _ => RouteStepKind.stairs,
        };
        final up = map.floorOf(to.regionId) >= map.floorOf(from.regionId);
        final what = switch (kind) {
          RouteStepKind.escalator => 'the escalator',
          RouteStepKind.elevator => 'the elevator',
          _ => 'the stairs',
        };
        final hints = <String>[for (var k = i; k <= j; k++) ?hintAt(k)];
        items.add(
          RouteStep(
            kind: kind,
            title:
                'Take $what ${up ? 'up' : 'down'} to ${map.levelLabel(to.regionId)}',
            hint: hints.isEmpty ? null : hints.join(' '),
            points: [from.pos, to.pos],
            regionId: to.regionId,
            fromRegionId: from.regionId,
          ),
        );
        changes++;
        i = j + 1;
        continue;
      }
      var j = i;
      while (j + 1 < walkEnd && !isChange(j + 1)) {
        final d1 = nodes[j + 1].pos - nodes[j].pos;
        final d2 = nodes[j + 2].pos - nodes[j + 1].pos;
        if (_turn(d1, d2) != _Turn.straight) break;
        j++;
      }
      final mpp = map.metresPerPixel(nodes[i].regionId);
      final pts = [for (var k = i; k <= j + 1; k++) nodes[k].pos];
      items.add(
        _Walk(
          regionId: nodes[i].regionId,
          points: pts,
          hints: {for (var k = i; k <= j; k++) ?hintAt(k)}.toList(),
          end: nodes[j + 1],
          metres: _length(pts) * mpp,
        ),
      );
      i = j + 1;
    }

    // 2. Fold tiny walks (a few steps around a corner) into their neighbour.
    var merged = true;
    while (merged) {
      merged = false;
      for (var k = 1; k < items.length; k++) {
        final a = items[k - 1], b = items[k];
        if (a is! _Walk || b is! _Walk) continue;
        if (a.metres < 15 || b.metres < 15 || _sameTarget(a.end, b.end)) {
          items[k - 1] = a.merge(b);
          items.removeAt(k);
          merged = true;
          break;
        }
      }
    }

    // 3. Titles with turn directions.
    final steps = <RouteStep>[];
    var walkMetres = 0.0;
    Offset? lastDir;
    for (var k = 0; k < items.length; k++) {
      final it = items[k];
      if (it is RouteStep) {
        steps.add(it);
        lastDir = null;
        continue;
      }
      final w = it as _Walk;
      walkMetres += w.metres;
      final isLastWalk = !items.skip(k + 1).any((x) => x is _Walk);
      final target = isLastWalk && hasApproach
          ? destinationName
          : (w.end.label ?? _nodeName(w.end));
      final headTo = target == null ? '' : ' toward $target';
      final dist = _metres(w.metres);
      final firstDir = w.points[1] - w.points[0];
      final String title;
      if (steps.isEmpty) {
        title = startName == null
            ? 'Walk $dist$headTo'
            : 'From $startName, walk $dist$headTo';
      } else if (lastDir == null) {
        title = 'Step off and walk $dist$headTo';
      } else {
        title = switch (_turn(lastDir, firstDir)) {
          _Turn.left => 'Turn left and walk $dist$headTo',
          _Turn.right => 'Turn right and walk $dist$headTo',
          _Turn.straight => 'Continue $dist$headTo',
        };
      }
      steps.add(
        RouteStep(
          kind: RouteStepKind.walk,
          title: title,
          hint: w.hints.isEmpty
              ? null
              : w.hints.take(3).map(_sentence).join(' '),
          points: w.points,
          regionId: w.regionId,
          metres: w.metres,
        ),
      );
      lastDir = w.points.last - w.points[w.points.length - 2];
    }

    // 4. Arrival: which side of the corridor is the door on?
    final last = nodes.last;
    final name = destinationName ?? 'your destination';
    var side = '';
    String? arriveHint;
    final arrivePts = <Offset>[];
    if (hasApproach) {
      final corridor = nodes[nodes.length - 2];
      arrivePts.addAll([corridor.pos, last.pos]);
      walkMetres +=
          (last.pos - corridor.pos).distance *
          map.metresPerPixel(last.regionId);
      arriveHint = hintAt(edges.length - 1);
      if (lastDir != null) {
        side = switch (_turn(lastDir, last.pos - corridor.pos, threshold: 30)) {
          _Turn.left => 'left',
          _Turn.right => 'right',
          _Turn.straight => '',
        };
      }
    } else {
      arrivePts.add(last.pos);
    }
    if (destinationRect != null) arrivePts.add(destinationRect.center);
    // Drop an authored hint that contradicts the side we computed.
    if (arriveHint != null && side.isNotEmpty) {
      final other = side == 'left' ? 'right' : 'left';
      if (arriveHint.toLowerCase().contains('your $other')) arriveHint = null;
    }
    steps.add(
      RouteStep(
        kind: RouteStepKind.arrive,
        title: steps.isEmpty && !hasApproach
            ? 'You are at $name'
            : (side.isEmpty
                  ? 'Arrive at $name, straight ahead'
                  : 'Arrive at $name on your $side'),
        hint: arriveHint,
        points: arrivePts,
        regionId: last.regionId,
      ),
    );
    return MapRoute(
      nodeIds: path,
      steps: steps,
      walkMetres: walkMetres,
      levelChanges: changes,
    );
  }

  bool _sameTarget(MapNode a, MapNode b) =>
      a.label != null && a.label == b.label;

  String? _nodeName(MapNode n) => switch (n.kind) {
    'escalator' => 'the escalators',
    'elevator' => 'the elevators',
    'stairs' => 'the stairs',
    _ => null,
  };
}

class _Walk {
  _Walk({
    required this.regionId,
    required this.points,
    required this.hints,
    required this.end,
    required this.metres,
  });
  final String regionId;
  final List<Offset> points;
  final List<String> hints;
  final MapNode end;
  final double metres;

  _Walk merge(_Walk next) => _Walk(
    regionId: regionId,
    points: [...points, ...next.points.skip(1)],
    hints: [
      ...hints,
      for (final h in next.hints)
        if (!hints.contains(h)) h,
    ],
    end: next.end,
    metres: metres + next.metres,
  );
}

enum _Turn { left, right, straight }

/// Turn direction in image coordinates (y grows downward, so a positive
/// cross product is a clockwise, i.e. right, turn).
_Turn _turn(Offset d1, Offset d2, {double threshold = 40}) {
  if (d1.distance == 0 || d2.distance == 0) return _Turn.straight;
  final cross = d1.dx * d2.dy - d1.dy * d2.dx;
  final dot = d1.dx * d2.dx + d1.dy * d2.dy;
  final angle = math.atan2(cross, dot) * 180 / math.pi;
  if (angle.abs() < threshold) return _Turn.straight;
  return angle > 0 ? _Turn.right : _Turn.left;
}

String _sentence(String s) => RegExp(r'[.!?]$').hasMatch(s) ? s : '$s.';

/// Public for tests: "left", "right" or "straight".
String turnName(Offset d1, Offset d2) => _turn(d1, d2).name;

double _length(List<Offset> pts) {
  var s = 0.0;
  for (var i = 1; i < pts.length; i++) {
    s += (pts[i] - pts[i - 1]).distance;
  }
  return s;
}

String _metres(double m) {
  if (m < 15) return 'a few steps';
  final r = (m / 10).round() * 10;
  return 'about $r m';
}

/// Great-circle distance in metres.
double haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// The geo-tagged node nearest to a GPS fix, with its distance in metres.
(MapNode, double)? nearestGeoNode(
  OfficialMap map,
  double lat,
  double lng, {
  bool Function(MapNode)? where,
}) {
  (MapNode, double)? best;
  for (final n in map.nodes) {
    if (n.lat == null || n.lng == null) continue;
    if (where != null && !where(n)) continue;
    final d = haversine(lat, lng, n.lat!, n.lng!);
    if (best == null || d < best.$2) best = (n, d);
  }
  return best;
}
