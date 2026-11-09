import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../data/official_map.dart';

/// Maps GPS coordinates onto the main Salt Palace plan of the venue map
/// image (the `sp-L1` panel; the plan is drawn rotated, with west up).
///
/// An affine fit by least squares over the geo-anchored nodes of that panel,
/// in a local flat east/north metre frame around the venue. The L2/L3 and
/// Hyatt panels are insets not drawn to geographic scale, so they have no
/// projection.
class GeoProjection {
  GeoProjection._({
    required this.lat0,
    required this.lng0,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.tx,
    required this.ty,
    required this.residuals,
  });

  /// Origin of the local metre frame.
  final double lat0, lng0;

  /// image x = a·east + b·north + tx; image y = c·east + d·north + ty
  /// (east/north in metres from the origin).
  final double a, b, c, d, tx, ty;

  /// Fit error per anchor node id, in metres.
  final Map<String, double> residuals;

  static const _earth = 6371000.0;
  static const regionId = 'sp-L1';

  /// Fixes this far outside the building outline are off the drawn plan.
  static const offMapMetres = 150.0;

  static final _cache = Expando<GeoProjection>();

  /// The projection for [map] (cached), or null without enough anchors.
  static GeoProjection? of(OfficialMap map) {
    final p = _cache[map] ??= fit(map) ?? _none;
    return identical(p, _none) ? null : p;
  }

  static final _none = GeoProjection._(
    lat0: 0,
    lng0: 0,
    a: 0,
    b: 0,
    c: 0,
    d: 0,
    tx: 0,
    ty: 0,
    residuals: const {},
  );

  bool get _valid => (a * d - b * c).abs() > 1e-9;

  /// Least-squares affine fit from the geo anchors on the main plan.
  static GeoProjection? fit(OfficialMap map) {
    final anchors = [
      for (final n in map.nodes)
        if (n.hasGeo && n.regionId == regionId) n,
    ];
    if (anchors.length < 3) return null;
    final lat0 =
        anchors.map((n) => n.lat!).reduce((x, y) => x + y) / anchors.length;
    final lng0 =
        anchors.map((n) => n.lng!).reduce((x, y) => x + y) / anchors.length;
    final kLat = math.pi / 180 * _earth;
    final kLng = kLat * math.cos(lat0 * math.pi / 180);
    final rows = [
      for (final n in anchors)
        [(n.lng! - lng0) * kLng, (n.lat! - lat0) * kLat, 1.0],
    ];
    final cx = _leastSquares(rows, [for (final n in anchors) n.pos.dx]);
    final cy = _leastSquares(rows, [for (final n in anchors) n.pos.dy]);
    if (cx == null || cy == null) return null;
    final p = GeoProjection._(
      lat0: lat0,
      lng0: lng0,
      a: cx[0],
      b: cx[1],
      tx: cx[2],
      c: cy[0],
      d: cy[1],
      ty: cy[2],
      residuals: {},
    );
    if (!p._valid) return null;
    for (final n in anchors) {
      final (lat, lng) = p.toGeo(n.pos);
      p.residuals[n.id] = haversine(lat, lng, n.lat!, n.lng!);
    }
    return p;
  }

  /// Image px for a GPS position.
  Offset toImage(double lat, double lng) {
    final kLat = math.pi / 180 * _earth;
    final kLng = kLat * math.cos(lat0 * math.pi / 180);
    final e = (lng - lng0) * kLng, n = (lat - lat0) * kLat;
    return Offset(a * e + b * n + tx, c * e + d * n + ty);
  }

  /// GPS position for image px.
  (double, double) toGeo(Offset p) {
    final det = a * d - b * c;
    final x = p.dx - tx, y = p.dy - ty;
    final e = (d * x - b * y) / det, n = (-c * x + a * y) / det;
    final kLat = math.pi / 180 * _earth;
    final kLng = kLat * math.cos(lat0 * math.pi / 180);
    return (lat0 + n / kLat, lng0 + e / kLng);
  }

  /// Image px per metre (geometric mean of the two axes), for accuracy
  /// circles.
  double get pxPerMetre => math.sqrt((a * d - b * c).abs());

  /// Direction on the image (radians, atan2 of image x/y) for a compass
  /// heading in degrees from north.
  double imageAngle(double headingDeg) {
    final h = headingDeg * math.pi / 180;
    final e = math.sin(h), n = math.cos(h);
    return math.atan2(c * e + d * n, a * e + b * n);
  }

  double get rmsResidual {
    if (residuals.isEmpty) return 0;
    final s = residuals.values.fold(0.0, (acc, r) => acc + r * r);
    return math.sqrt(s / residuals.length);
  }

  double get maxResidual => residuals.values.fold(0.0, math.max);

  /// Solves the normal equations for a 3-parameter linear least squares.
  static List<double>? _leastSquares(List<List<double>> rows, List<double> t) {
    final m = List.generate(3, (_) => List.filled(4, 0.0));
    for (var k = 0; k < rows.length; k++) {
      final r = rows[k];
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          m[i][j] += r[i] * r[j];
        }
        m[i][3] += r[i] * t[k];
      }
    }
    for (var i = 0; i < 3; i++) {
      var piv = i;
      for (var r = i + 1; r < 3; r++) {
        if (m[r][i].abs() > m[piv][i].abs()) piv = r;
      }
      final tmp = m[i];
      m[i] = m[piv];
      m[piv] = tmp;
      if (m[i][i].abs() < 1e-12) return null;
      for (var r = 0; r < 3; r++) {
        if (r == i) continue;
        final f = m[r][i] / m[i][i];
        for (var j = i; j < 4; j++) {
          m[r][j] -= f * m[i][j];
        }
      }
    }
    return [for (var i = 0; i < 3; i++) m[i][3] / m[i][i]];
  }
}
