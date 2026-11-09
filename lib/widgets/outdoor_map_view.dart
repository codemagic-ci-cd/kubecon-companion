import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../outdoor/outdoor_map.dart';
import '../outdoor/outdoor_nav.dart';
import '../outdoor/outdoor_steps.dart';
import '../theme/brand.dart';

/// Colors of the outdoor map (brand dark theme).
abstract final class OutdoorColors {
  static const page = Brand.darkPage;
  static const street = Brand.darkSubtleHover; // #2E3646
  static const majorStreet = Brand.lightBody; // #3A4865, a lighter street
  static const path = Brand.darkSubtle; // #232A38
  static const label = Brand.darkBody; // #D2DBEE
  static const venue = Brand.darkCardTop; // #182238
  static const landmark = Brand.darkCardBottom; // #101A2C
}

/// The user's live position on the map.
class UserMarker {
  const UserMarker(this.pos, this.accuracy, {this.heading});
  final Offset pos;

  /// Metres.
  final double accuracy;

  /// Degrees from north.
  final double? heading;
}

/// Our own street map (OpenStreetMap data) in an [InteractiveViewer], with
/// the walking route, destination and live position on top. Strokes and
/// labels keep the same on-screen size at any zoom.
class OutdoorMapView extends StatefulWidget {
  const OutdoorMapView({
    super.key,
    required this.map,
    required this.target,
    this.plan,
    this.currentStep,
    this.user,
    this.initialFocus,
  });

  final OutdoorMap map;
  final OutdoorTarget target;
  final OutdoorPlan? plan;
  final int? currentStep;
  final UserMarker? user;

  /// World rect (metres) to show first.
  final Rect? initialFocus;

  @override
  State<OutdoorMapView> createState() => OutdoorMapViewState();
}

class OutdoorMapViewState extends State<OutdoorMapView>
    with TickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _camera = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final AnimationController _dash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Animation<Matrix4>? _cameraAnim;
  Size? _viewport;
  bool _placed = false;
  bool _hasPlaced = false;
  Rect? _lastTarget;

  @override
  void initState() {
    super.initState();
    _camera.addListener(() {
      final a = _cameraAnim;
      if (a != null) _transform.value = a.value;
    });
    _syncDash();
  }

  @override
  void didUpdateWidget(OutdoorMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDash();
  }

  void _syncDash() {
    if (widget.plan != null && !_dash.isAnimating) {
      _dash.repeat();
    } else if (widget.plan == null && _dash.isAnimating) {
      _dash.stop();
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _dash.dispose();
    _transform.dispose();
    super.dispose();
  }

  Size get _world => widget.map.size;

  double _fitScale(Size v) =>
      math.min(v.width / _world.width, v.height / _world.height);

  double _maxScale(Size v) => math.max(_fitScale(v) * 16, 4);

  EdgeInsets _margin(Size v) {
    final s = _fitScale(v);
    final mx = math.max(0.0, (v.width / s - _world.width) / 2);
    final my = math.max(0.0, (v.height / s - _world.height) / 2);
    return EdgeInsets.symmetric(horizontal: mx + 1, vertical: my + 1);
  }

  /// Keeps framed routes clear of the map buttons on the right.
  static const _framePadding = EdgeInsets.fromLTRB(28, 28, 72, 28);

  Matrix4 _matrixFor(Rect target, Size v) {
    final fit = _fitScale(v);
    var pad = _framePadding;
    if (v.width - pad.horizontal < 120) pad = const EdgeInsets.all(16);
    var s = math.min(
      (v.width - pad.horizontal) / math.max(1, target.width),
      (v.height - pad.vertical) / math.max(1, target.height),
    );
    s = s.clamp(fit, _maxScale(v));
    final margin = _margin(v);
    double clampAxis(double t, double view, double size, double mg) {
      final maxT = mg * s;
      final minT = view - (size + mg) * s;
      if (minT > maxT) return (minT + maxT) / 2;
      return t.clamp(minT, maxT);
    }

    final tx = clampAxis(
      pad.left + (v.width - pad.horizontal) / 2 - target.center.dx * s,
      v.width,
      _world.width,
      margin.horizontal / 2,
    );
    final ty = clampAxis(
      pad.top + (v.height - pad.vertical) / 2 - target.center.dy * s,
      v.height,
      _world.height,
      margin.vertical / 2,
    );
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, s, 1);
  }

  /// Animates the camera so [target] (world metres) fills the view.
  void animateTo(Rect target) {
    _lastTarget = target;
    final v = _viewport;
    // Not placed yet: the first placement jumps straight to [target]. (An
    // animation started now would begin from the identity transform.)
    if (v == null || !_hasPlaced) return;
    _cameraAnim = Matrix4Tween(
      begin: _transform.value.clone(),
      end: _matrixFor(target, v),
    ).animate(CurvedAnimation(parent: _camera, curve: Curves.easeInOutCubic));
    _camera.forward(from: 0);
  }

  void _place(Size v) {
    _hasPlaced = true;
    _camera.stop();
    _transform.value = _matrixFor(
      _lastTarget ?? widget.initialFocus ?? widget.map.bounds,
      v,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final v = Size(c.maxWidth, c.maxHeight);
        if (v.isEmpty) return const SizedBox.shrink();
        if (_viewport != v) {
          final first = !_placed;
          _viewport = v;
          _placed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (first || !_camera.isAnimating) _place(v);
          });
        }
        return ClipRect(
          child: ColoredBox(
            color: OutdoorColors.page,
            child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: _fitScale(v),
              maxScale: _maxScale(v),
              boundaryMargin: _margin(v),
              onInteractionStart: (_) => _camera.stop(),
              child: SizedBox(
                width: _world.width,
                height: _world.height,
                child: CustomPaint(
                  painter: OutdoorMapPainter(
                    map: widget.map,
                    target: widget.target,
                    plan: widget.plan,
                    currentStep: widget.currentStep,
                    user: widget.user,
                    transform: _transform,
                    dash: _dash,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paths built once per map.
class _MapCache {
  _MapCache(OutdoorMap map) {
    final major = {for (final l in map.labels) l.name};
    for (final e in map.edges) {
      final a = map.nodes[e.a], b = map.nodes[e.b];
      final p = switch (e.kind) {
        OutdoorEdgeKind.street =>
          major.contains(map.nameOf(e.name)) ? majorStreets : streets,
        _ => paths,
      };
      p
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    for (final b in map.buildings) {
      if (b.outline.length < 3) continue;
      buildings[b] = Path()..addPolygon(b.outline, true);
    }
    for (final l in map.labels) {
      labelAngles[l] = _labelAngle(map, l);
    }
  }

  final streets = Path();
  final majorStreets = Path();
  final paths = Path();
  final buildings = <OutdoorBuilding, Path>{};
  final labelAngles = <StreetLabel, double>{};

  static final _all = Expando<_MapCache>();
  static _MapCache of(OutdoorMap m) => _all[m] ??= _MapCache(m);

  /// Aligns a label with the nearest street of the same name, kept
  /// readable (never upside down).
  static double _labelAngle(OutdoorMap map, StreetLabel l) {
    var best = double.infinity;
    double? angle;
    for (final e in map.edges) {
      if (map.nameOf(e.name) != l.name) continue;
      final a = map.nodes[e.a], b = map.nodes[e.b];
      final (d, _) = segmentDistance(l.pos, a, b);
      if (d < best && (b - a).distance > 1) {
        best = d;
        angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      }
    }
    var r = angle ?? -l.angle * math.pi / 180;
    while (r > math.pi / 2) {
      r -= math.pi;
    }
    while (r <= -math.pi / 2) {
      r += math.pi;
    }
    return r;
  }
}

class OutdoorMapPainter extends CustomPainter {
  OutdoorMapPainter({
    required this.map,
    required this.target,
    required this.plan,
    required this.currentStep,
    required this.user,
    required this.transform,
    required this.dash,
  }) : super(repaint: Listenable.merge([transform, dash]));

  final OutdoorMap map;
  final OutdoorTarget target;
  final OutdoorPlan? plan;
  final int? currentStep;
  final UserMarker? user;
  final TransformationController transform;
  final Animation<double> dash;

  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c
    ..strokeWidth = w;

  @override
  void paint(Canvas canvas, Size size) {
    final m = transform.value.storage;
    final s = math.sqrt(m[0] * m[0] + m[1] * m[1]).clamp(0.01, 100.0);
    double px(double screen) => screen / s;
    final cache = _MapCache.of(map);

    // Buildings.
    for (final e in cache.buildings.entries) {
      final b = e.key;
      final fill = b == target.building
          ? Brand.neverBlue.withValues(alpha: 0.28)
          : b.kind == OutdoorBuildingKind.venue
          ? OutdoorColors.venue
          : OutdoorColors.landmark;
      canvas.drawPath(e.value, Paint()..color = fill);
      if (b == target.building) {
        canvas.drawPath(e.value, _stroke(Brand.neverBlue, px(2)));
      }
    }

    // Streets and paths.
    canvas.drawPath(cache.paths, _stroke(OutdoorColors.path, px(2)));
    canvas.drawPath(cache.streets, _stroke(OutdoorColors.street, px(7)));
    canvas.drawPath(
      cache.majorStreets,
      _stroke(OutdoorColors.majorStreet, px(10)),
    );

    // Labels.
    for (final l in map.labels) {
      _text(
        canvas,
        l.name,
        l.pos,
        11,
        OutdoorColors.label,
        s,
        angle: cache.labelAngles[l] ?? 0,
        halo: 3,
      );
    }
    for (final b in map.buildings) {
      if (b.kind != OutdoorBuildingKind.venue || b.name.isEmpty) continue;
      final outline = cache.buildings[b];
      _text(
        canvas,
        b.name,
        b.centroid,
        12,
        Colors.white,
        s,
        weight: FontWeight.w600,
        halo: 3,
        // Only when the name fits inside the building at this zoom.
        maxWidth: outline == null ? null : outline.getBounds().width * 0.9,
      );
    }

    final p = plan;
    if (p != null) _paintRoute(canvas, p, px);

    // The venue itself; when it sits back from the path the route ends on,
    // a dotted line joins the two.
    final routeEnd = p?.route.end ?? target.point.pos;
    if ((target.venuePos - routeEnd).distance > 6) {
      _dotted(canvas, routeEnd, target.venuePos, Brand.neverBlue, px);
    }
    _pin(canvas, target.venuePos, px, Brand.neverBlue);

    final u = user;
    if (u != null) {
      // Off the path (e.g. inside a building or a plaza): dotted line to the
      // nearest point of the route.
      if (p != null && p.route.metres > 0) {
        final (dist, along) = p.route.nearest(u.pos);
        if (dist > 8) {
          _dotted(canvas, u.pos, p.route.pointAt(along), Brand.neverBlue, px);
        }
      }
      _paintUser(canvas, u, px);
    }
  }

  void _dotted(
    Canvas canvas,
    Offset a,
    Offset b,
    Color c,
    double Function(double) px,
  ) {
    final len = (b - a).distance;
    final gap = px(7);
    if (len <= 0 || gap <= 0) return;
    final n = (len / gap).floor();
    final halo = Paint()..color = Colors.white;
    final dot = Paint()..color = c;
    for (var i = 0; i <= n; i++) {
      final q = Offset.lerp(a, b, i * gap / len)!;
      canvas.drawCircle(q, px(2.6), halo);
      canvas.drawCircle(q, px(1.8), dot);
    }
  }

  void _paintRoute(Canvas canvas, OutdoorPlan p, double Function(double) px) {
    final pts = p.route.points;
    if (pts.length > 1) {
      canvas.drawPath(_path(pts), _stroke(Colors.white, px(9)));
      final period = px(22);
      _dashed(
        canvas,
        pts,
        _stroke(Brand.swwYellow, px(5))..strokeCap = StrokeCap.butt,
        on: px(13),
        off: px(9),
        phase: dash.value * period,
      );
    }
    final cur = currentStep;
    if (cur != null && cur >= 0 && cur < p.steps.length) {
      final st = p.steps[cur];
      if (st.points.length > 1) {
        canvas.drawPath(_path(st.points), _stroke(Colors.white, px(13)));
        canvas.drawPath(_path(st.points), _stroke(Brand.swwYellow, px(8)));
      }
      // Where the step ends.
      final end = st.end;
      if (st.kind != OutdoorStepKind.arrive) {
        canvas.drawCircle(end, px(7), Paint()..color = Colors.white);
        canvas.drawCircle(end, px(4.5), Paint()..color = Brand.swwYellow);
      }
    }
    // Start.
    final start = p.route.start;
    canvas.drawCircle(start, px(11), Paint()..color = Colors.white);
    canvas.drawCircle(start, px(7), Paint()..color = Brand.noBugBlue);
    canvas.drawCircle(start, px(3), Paint()..color = Colors.white);
  }

  void _paintUser(Canvas canvas, UserMarker u, double Function(double) px) {
    if (u.accuracy.isFinite && u.accuracy > 0) {
      canvas.drawCircle(
        u.pos,
        u.accuracy,
        Paint()..color = Brand.neverBlue.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        u.pos,
        u.accuracy,
        _stroke(Brand.neverBlue.withValues(alpha: 0.5), px(1)),
      );
    }
    final h = u.heading;
    if (h != null) {
      final r = px(30);
      final rad = (h - 90) * math.pi / 180;
      final cone = Path()
        ..moveTo(u.pos.dx, u.pos.dy)
        ..arcTo(
          Rect.fromCircle(center: u.pos, radius: r),
          rad - 0.5,
          1.0,
          false,
        )
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Brand.neverBlue.withValues(alpha: 0.6),
              Brand.neverBlue.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: u.pos, radius: r)),
      );
    }
    canvas.drawCircle(u.pos, px(10), Paint()..color = Colors.white);
    canvas.drawCircle(u.pos, px(7), Paint()..color = Brand.neverBlue);
  }

  /// Text laid out once at its on-screen size and drawn with the zoom
  /// undone, so labels stay the same size without re-layout every frame.
  static final _textCache = <String, TextPainter>{};

  static TextPainter _laidOut(
    String text,
    double size,
    FontWeight weight,
    Color color,
    double halo,
  ) => _textCache.putIfAbsent(
    '$text|$size|${weight.value}|${color.toARGB32()}|$halo',
    () => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: -0.2 * size / 14,
          color: halo > 0 ? null : color,
          foreground: halo > 0
              ? (Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = halo
                  ..strokeJoin = StrokeJoin.round
                  ..color = color)
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );

  /// [size] and [halo] are screen pixels; [zoom] is the current scale;
  /// [maxWidth] is in world metres (skip the label when it is wider).
  void _text(
    Canvas canvas,
    String text,
    Offset at,
    double size,
    Color color,
    double zoom, {
    double angle = 0,
    double halo = 0,
    FontWeight weight = FontWeight.w400,
    double? maxWidth,
  }) {
    final t = _laidOut(text, size, weight, color, 0);
    if (maxWidth != null && t.width / zoom > maxWidth) return;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (angle != 0) canvas.rotate(angle);
    canvas.scale(1 / zoom);
    if (halo > 0) {
      final h = _laidOut(text, size, weight, OutdoorColors.page, halo);
      h.paint(canvas, Offset(-h.width / 2, -h.height / 2));
    }
    t.paint(canvas, Offset(-t.width / 2, -t.height / 2));
    canvas.restore();
  }

  void _pin(Canvas canvas, Offset tip, double Function(double) px, Color c) {
    final h = px(34), r = px(11);
    final center = tip - Offset(0, h - r);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        center.dx - r * 1.1,
        center.dy + r * 0.9,
        center.dx - r,
        center.dy,
      )
      ..arcToPoint(Offset(center.dx + r, center.dy), radius: Radius.circular(r))
      ..quadraticBezierTo(
        center.dx + r * 1.1,
        center.dy + r * 0.9,
        tip.dx,
        tip.dy,
      )
      ..close();
    canvas.drawPath(path, _stroke(Colors.white, px(3)));
    canvas.drawPath(path, Paint()..color = c);
    canvas.drawCircle(center, r * 0.42, Paint()..color = Colors.white);
  }

  Path _path(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    return p;
  }

  void _dashed(
    Canvas canvas,
    List<Offset> pts,
    Paint paint, {
    required double on,
    required double off,
    required double phase,
  }) {
    final path = _path(pts);
    for (final metric in path.computeMetrics()) {
      var d = -(on + off) + (phase % (on + off));
      while (d < metric.length) {
        final a = math.max(0.0, d), b = math.min(metric.length, d + on);
        if (b > a) canvas.drawPath(metric.extractPath(a, b), paint);
        d += on + off;
      }
    }
  }

  @override
  bool shouldRepaint(OutdoorMapPainter old) =>
      old.map != map ||
      old.target != target ||
      old.plan != plan ||
      old.currentStep != currentStep ||
      old.user != user;
}
