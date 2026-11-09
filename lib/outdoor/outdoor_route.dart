import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'outdoor_map.dart';

/// One straight piece of a walking route.
class RouteLeg {
  const RouteLeg(this.a, this.b, this.name, this.kind);
  final Offset a, b;

  /// Index into [OutdoorMap.names], or -1.
  final int name;
  final OutdoorEdgeKind kind;
  double get metres => (b - a).distance;
}

/// A walking route as straight legs from start to end.
class OutdoorRoute {
  OutdoorRoute(this.legs, {required this.start, required this.end}) {
    var d = 0.0;
    for (final l in legs) {
      _cum.add(d);
      d += l.metres;
    }
    metres = d;
  }

  final List<RouteLeg> legs;
  final Offset start, end;
  final _cum = <double>[];
  late final double metres;

  /// Walking time at [walkMetresPerMinute], at least a minute.
  int get minutes => walkMinutes(metres);

  List<Offset> get points =>
      legs.isEmpty ? [start, end] : [legs.first.a, for (final l in legs) l.b];

  /// Distance along the route where leg [i] starts.
  double legStart(int i) => i < _cum.length ? _cum[i] : metres;

  /// Distance from [p] to the route and how far along the nearest point is.
  (double distance, double along) nearest(Offset p) {
    if (legs.isEmpty) return ((p - end).distance, 0);
    var best = double.infinity, along = 0.0;
    for (var i = 0; i < legs.length; i++) {
      final l = legs[i];
      final (d, t) = segmentDistance(p, l.a, l.b);
      if (d < best) {
        best = d;
        along = _cum[i] + t * l.metres;
      }
    }
    return (best, along);
  }

  /// Polyline between two distances along the route.
  List<Offset> slice(double from, double to) {
    final out = <Offset>[];
    for (var i = 0; i < legs.length; i++) {
      final l = legs[i];
      final s = _cum[i], e = s + l.metres;
      if (e < from || s > to) continue;
      Offset at(double d) =>
          l.metres == 0 ? l.a : Offset.lerp(l.a, l.b, (d - s) / l.metres)!;
      final a = at(math.max(from, s)), b = at(math.min(to, e));
      if (out.isEmpty || (out.last - a).distance > 0.01) out.add(a);
      out.add(b);
    }
    if (out.isEmpty) out.add(legs.isEmpty ? end : legs.last.b);
    return out;
  }

  /// Point at a distance along the route.
  Offset pointAt(double d) => slice(d, d).first;
}

const walkMetresPerMinute = 80.0;

int walkMinutes(double metres) =>
    math.max(1, (metres / walkMetresPerMinute).ceil());

/// "120 m", "1.2 km".
String formatMetres(double m) {
  if (m >= 1000) {
    final km = (m / 100).round() / 10;
    return '${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1)} km';
  }
  return '${math.max(10, (m / 10).round() * 10)} m';
}

/// Shortest walking paths on an [OutdoorMap].
class OutdoorRouter {
  OutdoorRouter(this.map);
  final OutdoorMap map;

  List<(int, double)> _seeds(GraphPoint p) {
    if (p.node != null) return [(p.node!, 0)];
    final e = map.edges[p.edge!];
    return [(e.a, p.t * e.cost), (e.b, (1 - p.t) * e.cost)];
  }

  /// Costs from [from] to every node (Dijkstra).
  List<double> costsFrom(GraphPoint from) {
    final dist = List.filled(map.nodes.length, double.infinity);
    final heap = _Heap();
    for (final (n, c) in _seeds(from)) {
      if (c < dist[n]) {
        dist[n] = c;
        heap.push(c, n);
      }
    }
    while (heap.isNotEmpty) {
      final (c, n) = heap.pop();
      if (c > dist[n]) continue;
      for (final ei in map.adjacency[n]) {
        final e = map.edges[ei];
        final m = e.other(n), nc = c + e.cost;
        if (nc < dist[m]) {
          dist[m] = nc;
          heap.push(nc, m);
        }
      }
    }
    return dist;
  }

  /// Cheapest route (A*, cost = [OutdoorEdge.cost]), or null when the two
  /// points are not connected.
  OutdoorRoute? route(GraphPoint from, GraphPoint to) {
    final nodes = map.nodes;
    // Same edge: walk straight along it.
    if (from.edge != null && from.edge == to.edge) {
      final e = map.edges[from.edge!];
      return OutdoorRoute(
        [RouteLeg(from.pos, to.pos, e.name, e.kind)],
        start: from.pos,
        end: to.pos,
      );
    }
    final targets = <int, double>{for (final (n, c) in _seeds(to)) n: c};
    final dist = List.filled(nodes.length, double.infinity);
    final prevEdge = List.filled(nodes.length, -1);
    final heap = _Heap();
    double h(int n) => (nodes[n] - to.pos).distance;
    for (final (n, c) in _seeds(from)) {
      if (c < dist[n]) {
        dist[n] = c;
        heap.push(c + h(n), n);
      }
    }
    var best = double.infinity;
    int? bestNode;
    while (heap.isNotEmpty) {
      final (f, n) = heap.pop();
      if (f >= best) break;
      final c = dist[n];
      if (f > c + h(n) + 1e-9) continue;
      final extra = targets[n];
      if (extra != null && c + extra < best) {
        best = c + extra;
        bestNode = n;
      }
      for (final ei in map.adjacency[n]) {
        final e = map.edges[ei];
        final m = e.other(n), nc = c + e.cost;
        if (nc < dist[m]) {
          dist[m] = nc;
          prevEdge[m] = ei;
          heap.push(nc + h(m), m);
        }
      }
    }
    if (bestNode == null) return null;

    // Walk back to the start.
    final pathEdges = <int>[];
    final pathNodes = <int>[bestNode];
    var n = bestNode;
    // Nodes without a previous edge are start seeds.
    while (prevEdge[n] != -1) {
      final ei = prevEdge[n];
      pathEdges.add(ei);
      n = map.edges[ei].other(n);
      pathNodes.add(n);
    }
    final ordered = pathNodes.reversed.toList();
    final orderedEdges = pathEdges.reversed.toList();
    final legs = <RouteLeg>[];
    void add(Offset a, Offset b, int name, OutdoorEdgeKind kind) {
      if ((b - a).distance > 0.05) legs.add(RouteLeg(a, b, name, kind));
    }

    if (from.edge != null) {
      final e = map.edges[from.edge!];
      add(from.pos, nodes[ordered.first], e.name, e.kind);
    }
    for (var i = 0; i < orderedEdges.length; i++) {
      final e = map.edges[orderedEdges[i]];
      add(nodes[ordered[i]], nodes[ordered[i + 1]], e.name, e.kind);
    }
    if (to.edge != null) {
      final e = map.edges[to.edge!];
      add(nodes[ordered.last], to.pos, e.name, e.kind);
    }
    return OutdoorRoute(legs, start: from.pos, end: to.pos);
  }
}

/// Minimal binary min-heap of (priority, value).
class _Heap {
  final _p = <double>[];
  final _v = <int>[];

  bool get isNotEmpty => _p.isNotEmpty;

  void push(double p, int v) {
    _p.add(p);
    _v.add(v);
    var i = _p.length - 1;
    while (i > 0) {
      final up = (i - 1) >> 1;
      if (_p[up] <= _p[i]) break;
      _swap(i, up);
      i = up;
    }
  }

  (double, int) pop() {
    final top = (_p.first, _v.first);
    final lp = _p.removeLast(), lv = _v.removeLast();
    if (_p.isNotEmpty) {
      _p[0] = lp;
      _v[0] = lv;
      var i = 0;
      while (true) {
        final l = i * 2 + 1, r = l + 1;
        var m = i;
        if (l < _p.length && _p[l] < _p[m]) m = l;
        if (r < _p.length && _p[r] < _p[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final p = _p[a];
    _p[a] = _p[b];
    _p[b] = p;
    final v = _v[a];
    _v[a] = _v[b];
    _v[b] = v;
  }
}
