import 'dart:math' as math;

import '../data/official_map.dart';

/// How a GPS fix was turned into a route start.
enum GeoStartKind {
  /// In or right next to the building: start at the nearest indoor anchor.
  indoor,

  /// Within walking distance: walk outside to the nearest street entrance.
  nearby,

  /// Too far, too inaccurate or no fix: start at the main entrance.
  fallback,
}

/// Why a fix was not used.
enum GeoFallbackReason { unavailable, inaccurate, tooFar }

/// The chosen start for a GPS fix (or the lack of one).
class GeoStart {
  const GeoStart({
    required this.kind,
    required this.node,
    this.outdoorMetres = 0,
    this.reason,
  });

  final GeoStartKind kind;

  /// Graph node the indoor route starts from.
  final MapNode node;

  /// Straight-line distance from the fix to [node] for [GeoStartKind.nearby].
  final double outdoorMetres;
  final GeoFallbackReason? reason;

  /// Rounded outdoor walking distance ("about 450 m").
  int get outdoorMetresRounded =>
      math.max(10, (outdoorMetres / 10).round() * 10);

  /// Outdoor walking time at ~75 m/min, at least a minute.
  int get outdoorMinutes => math.max(1, (outdoorMetres / 75).ceil());

  /// Short place name of the start node.
  String get placeName => node.place ?? node.label ?? 'the venue';
}

/// Start-point selection thresholds.
class GeoStartRules {
  const GeoStartRules._();

  /// Fixes this close to (or inside) the footprint count as indoors.
  static const indoorMetres = 60.0;

  /// Beyond this, walking directions to an entrance stop making sense.
  static const maxOutdoorMetres = 3000.0;

  /// Fixes less precise than this are ignored.
  static const maxAccuracyMetres = 150.0;
}

/// Picks where a route should start for a GPS fix.
///
/// [lat]/[lng]/[accuracy] are null when no fix is available (permission
/// denied, unsupported, timed out). GPS has no floor, so indoor fixes snap to
/// ground-level (Salt Palace Level 1) anchors only.
GeoStart chooseGeoStart(
  OfficialMap map, {
  double? lat,
  double? lng,
  double? accuracy,
}) {
  final main = map.node(OfficialMap.mainEntranceId) ?? map.nodes.first;
  GeoStart fallback(GeoFallbackReason r) =>
      GeoStart(kind: GeoStartKind.fallback, node: main, reason: r);

  if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
    return fallback(GeoFallbackReason.unavailable);
  }
  if (accuracy == null ||
      !accuracy.isFinite ||
      accuracy > GeoStartRules.maxAccuracyMetres) {
    return fallback(GeoFallbackReason.inaccurate);
  }
  final ground = groundAnchors(map);
  if (ground.isEmpty) return fallback(GeoFallbackReason.unavailable);

  final away = distanceToFootprint(map, lat, lng);
  if (away <= GeoStartRules.indoorMetres) {
    final hit = nearestGeoNode(map, lat, lng, where: ground.contains)!;
    return GeoStart(kind: GeoStartKind.indoor, node: hit.$1);
  }
  final street = ground.where((n) => n.street).toSet();
  final hit = nearestGeoNode(
    map,
    lat,
    lng,
    where: street.isEmpty ? ground.contains : street.contains,
  )!;
  if (hit.$2 > GeoStartRules.maxOutdoorMetres) {
    return fallback(GeoFallbackReason.tooFar);
  }
  return GeoStart(
    kind: GeoStartKind.nearby,
    node: hit.$1,
    outdoorMetres: hit.$2,
  );
}

/// Geo-anchored nodes on the street level (Salt Palace Level 1, which also
/// holds the Hyatt lobby).
List<MapNode> groundAnchors(OfficialMap map) => [
  for (final n in map.nodes)
    if (n.hasGeo && map.floorOf(n.regionId) == 1) n,
];

/// Metres from a point to the building footprint; 0 inside it. Without a
/// footprint, the bounding box of the geo anchors stands in for it.
double distanceToFootprint(OfficialMap map, double lat, double lng) {
  var poly = map.footprint;
  if (poly.length < 3) {
    final pts = [
      for (final n in map.nodes)
        if (n.hasGeo) (n.lat!, n.lng!),
    ];
    if (pts.isEmpty) return double.infinity;
    final las = pts.map((p) => p.$1), lns = pts.map((p) => p.$2);
    final s = las.reduce(math.min), n = las.reduce(math.max);
    final w = lns.reduce(math.min), e = lns.reduce(math.max);
    poly = [(s, w), (s, e), (n, e), (n, w)];
  }
  // Local flat projection in metres around the point.
  const r = 6371000.0;
  final kLat = math.pi / 180 * r;
  final kLng = kLat * math.cos(lat * math.pi / 180);
  final xy = [for (final p in poly) ((p.$2 - lng) * kLng, (p.$1 - lat) * kLat)];

  var inside = false;
  var best = double.infinity;
  for (var i = 0, j = xy.length - 1; i < xy.length; j = i++) {
    final (xi, yi) = xy[i];
    final (xj, yj) = xy[j];
    if ((yi > 0) != (yj > 0) && 0 < (xj - xi) * (0 - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
    best = math.min(best, _segDist(xi, yi, xj, yj));
  }
  return inside ? 0 : best;
}

/// Distance from the origin to segment (ax, ay)-(bx, by).
double _segDist(double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0
      ? 0.0
      : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0).toDouble();
  final px = ax + t * dx, py = ay + t * dy;
  return math.sqrt(px * px + py * py);
}

/// Walking directions to a node in the platform maps app. Only the
/// destination (a public venue coordinate) goes in the URL; the maps app
/// fills in the user's own position.
String walkingDirectionsUrl(MapNode node) =>
    'https://www.google.com/maps/dir/?api=1'
    '&destination=${node.lat},${node.lng}&travelmode=walking';
