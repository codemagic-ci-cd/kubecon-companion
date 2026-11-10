import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';

import '../data/official_map.dart';
import '../location/live_location.dart';
import '../theme/brand.dart';

/// The official venue map image in an [InteractiveViewer], with our room
/// highlight and route drawn on top in image coordinates.
class OfficialMapView extends StatefulWidget {
  const OfficialMapView({
    super.key,
    required this.map,
    this.selectedRoomId,
    this.selectedRect,
    this.route,
    this.currentStep,
    this.onRoomTap,
    this.initialFocus,
    this.liveLocation,
    this.onUserMove,
    this.spotPin,
  });

  final OfficialMap map;
  final String? selectedRoomId;

  /// Overrides the selected room's box (e.g. for a room drawn as part of a
  /// bigger one).
  final Rect? selectedRect;
  final MapRoute? route;
  final int? currentStep;
  final ValueChanged<String>? onRoomTap;

  /// Image-space rect to show first instead of the whole map.
  final Rect? initialFocus;

  /// The device position, drawn as a blue dot on its own layer.
  final ValueListenable<LivePlacement?>? liveLocation;

  /// The user started panning or zooming.
  final VoidCallback? onUserMove;

  /// Image px of a shared spot ("Share my spot"), drawn as a yellow person
  /// pin.
  final Offset? spotPin;

  @override
  State<OfficialMapView> createState() => OfficialMapViewState();
}

class OfficialMapViewState extends State<OfficialMapView>
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
  (Rect, double, double)? _lastTarget;

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
  void didUpdateWidget(OfficialMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDash();
  }

  void _syncDash() {
    if (widget.route != null && !_dash.isAnimating) {
      _dash.repeat();
    } else if (widget.route == null && _dash.isAnimating) {
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

  double _fitScale(Size v) =>
      math.min(v.width / widget.map.width, v.height / widget.map.height);

  double _maxScale(Size v) => math.max(_fitScale(v) * 6, 1.2);

  /// Extra pannable margin (image px) so the fitted map can stay centred.
  EdgeInsets _margin(Size v) {
    final s = _fitScale(v);
    final mx = math.max(0.0, (v.width / s - widget.map.width) / 2);
    final my = math.max(0.0, (v.height / s - widget.map.height) / 2);
    return EdgeInsets.symmetric(horizontal: mx + 1, vertical: my + 1);
  }

  /// [bottomFraction] keeps the target in the part of the view above a
  /// bottom sheet covering that fraction of the height.
  Matrix4 _matrixFor(
    Rect target,
    Size v, {
    double padding = 24,
    double bottomFraction = 0,
  }) {
    final m = widget.map;
    final fit = _fitScale(v);
    final visibleH = v.height * (1 - bottomFraction);
    var s = math.min(
      (v.width - padding * 2) / target.width,
      (visibleH - padding * 2) / target.height,
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
      v.width / 2 - target.center.dx * s,
      v.width,
      m.width,
      margin.horizontal / 2,
    );
    final ty = clampAxis(
      visibleH / 2 - target.center.dy * s,
      v.height,
      m.height,
      margin.vertical / 2,
    );
    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      // Scale z too, like InteractiveViewer does, so getMaxScaleOnAxis()
      // reports the real zoom when zoomed out.
      ..scaleByDouble(s, s, s, 1);
  }

  /// Animates the camera so [target] (image px) fills the view.
  void animateTo(
    Rect target, {
    double padding = 24,
    double bottomFraction = 0,
  }) {
    _lastTarget = (target, padding, bottomFraction);
    final v = _viewport;
    if (v == null) return;
    _cameraAnim = Matrix4Tween(
      begin: _transform.value.clone(),
      end: _matrixFor(
        target,
        v,
        padding: padding,
        bottomFraction: bottomFraction,
      ),
    ).animate(CurvedAnimation(parent: _camera, curve: Curves.easeInOutCubic));
    _camera.forward(from: 0);
  }

  void fit() => animateTo(widget.map.bounds, padding: 0);

  /// Pans so [p] (image px) is centred, zooming in to show at most [span]
  /// image px across the shorter side but never zooming out.
  void centerOn(Offset p, {double span = 480}) {
    final v = _viewport;
    if (v == null) {
      _lastTarget = (
        Rect.fromCenter(center: p, width: span, height: span),
        0,
        0,
      );
      return;
    }
    final cur = _transform.value.getMaxScaleOnAxis();
    final s = math.max(cur, math.min(v.width, v.height) / span);
    animateTo(
      Rect.fromCenter(center: p, width: v.width / s, height: v.height / s),
      padding: 0,
    );
  }

  void _place(Size v) {
    final last = _lastTarget;
    final focus = widget.initialFocus;
    _transform.value = last != null
        ? _matrixFor(last.$1, v, padding: last.$2, bottomFraction: last.$3)
        : _matrixFor(
            focus ?? widget.map.bounds,
            v,
            padding: focus == null ? 0 : 24,
          );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.map;
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
            // Re-frame on first layout and when the view size changes
            // (rotation, window resize) so the map never sits off-centre.
            if (first || !_camera.isAnimating) _place(v);
          });
        }
        final selected =
            widget.selectedRect ?? m.rooms[widget.selectedRoomId]?.rect;
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            minScale: _fitScale(v),
            maxScale: _maxScale(v),
            boundaryMargin: _margin(v),
            onInteractionStart: (_) {
              _camera.stop();
              widget.onUserMove?.call();
            },
            child: GestureDetector(
              onTapUp: widget.onRoomTap == null
                  ? null
                  : (d) {
                      final id = m.roomAt(d.localPosition);
                      if (id != null) widget.onRoomTap!(id);
                    },
              child: SizedBox(
                width: m.width,
                height: m.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        m.image,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        errorBuilder: (context, _, _) =>
                            const ColoredBox(color: Colors.white),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: MapOverlayPainter(
                          map: m,
                          selected: selected,
                          route: widget.route,
                          currentStep: widget.currentStep,
                          transform: _transform,
                          dash: _dash,
                          spot: widget.spotPin,
                        ),
                      ),
                    ),
                    if (widget.liveLocation != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: LiveDotLayer(
                              placement: widget.liveLocation!,
                              transform: _transform,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Draws in image coordinates; stroke widths are divided by the current
/// zoom so they look the same on screen at any scale.
class MapOverlayPainter extends CustomPainter {
  MapOverlayPainter({
    required this.map,
    required this.selected,
    required this.route,
    required this.currentStep,
    required this.transform,
    required this.dash,
    this.spot,
  }) : super(repaint: Listenable.merge([transform, dash]));

  final OfficialMap map;
  final Rect? selected;
  final MapRoute? route;
  final int? currentStep;
  final TransformationController transform;
  final Animation<double> dash;

  /// Shared spot pin position (image px).
  final Offset? spot;

  @override
  void paint(Canvas canvas, Size size) {
    // Zoom along x (the view never rotates).
    final m = transform.value.storage;
    final s = math.sqrt(m[0] * m[0] + m[1] * m[1]).clamp(0.01, 100.0);
    double px(double screen) => screen / s;

    final sel = selected;
    if (sel != null) {
      final r = RRect.fromRectAndRadius(sel, Radius.circular(px(6)));
      canvas.drawRRect(
        r,
        Paint()..color = Brand.neverBlue.withValues(alpha: 0.28),
      );
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = px(3)
          ..color = Brand.neverBlue,
      );
    }

    final rt = route;
    if (rt != null) _paintRoute(canvas, rt, px);

    if (sel != null) {
      final tip = rt != null && rt.steps.last.points.isNotEmpty
          ? rt.steps.last.points.last
          : sel.center;
      _pin(canvas, tip, px, Brand.neverBlue);
    }

    final sp = spot;
    if (sp != null) _spotPin(canvas, sp, px);
  }

  /// Bigger SWW Yellow pin with a person icon for a shared spot.
  void _spotPin(Canvas canvas, Offset tip, double Function(double) px) {
    final h = px(44), r = px(15);
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
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = px(3),
    );
    canvas.drawPath(path, Paint()..color = Brand.swwYellow);
    const icon = Icons.person;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: r * 1.4,
          color: Brand.darkPage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintRoute(Canvas canvas, MapRoute rt, double Function(double) px) {
    final casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white
      ..strokeWidth = px(9);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Brand.swwYellow
      ..strokeWidth = px(5);

    final walkSteps = [
      for (var i = 0; i < rt.steps.length; i++)
        if (!rt.steps[i].isLevelChange && rt.steps[i].points.length > 1) i,
    ];
    for (final i in walkSteps) {
      canvas.drawPath(_path(rt.steps[i].points), casing);
    }
    final period = px(22);
    for (final i in walkSteps) {
      _dashed(
        canvas,
        rt.steps[i].points,
        line,
        on: px(13),
        off: px(9),
        phase: dash.value * period,
      );
    }

    // Emphasize the current step.
    final cur = currentStep;
    if (cur != null && cur >= 0 && cur < rt.steps.length) {
      final st = rt.steps[cur];
      if (!st.isLevelChange && st.points.length > 1) {
        canvas.drawPath(
          _path(st.points),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white
            ..strokeWidth = px(13),
        );
        canvas.drawPath(
          _path(st.points),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Brand.swwYellow
            ..strokeWidth = px(8),
        );
      }
    }

    // Level-change markers at both ends.
    for (var i = 0; i < rt.steps.length; i++) {
      final st = rt.steps[i];
      if (!st.isLevelChange) continue;
      final active = i == cur;
      for (final p in st.points) {
        _connector(canvas, p, px, st.kind, active);
      }
    }

    // Start pin.
    final first = rt.steps.first.points;
    if (first.isNotEmpty) {
      final p = first.first;
      canvas.drawCircle(p, px(11), Paint()..color = Colors.white);
      canvas.drawCircle(p, px(7), Paint()..color = Brand.noBugBlue);
      canvas.drawCircle(p, px(3), Paint()..color = Colors.white);
    }
  }

  void _connector(
    Canvas canvas,
    Offset p,
    double Function(double) px,
    RouteStepKind kind,
    bool active,
  ) {
    final r = px(active ? 16 : 13);
    if (active) {
      canvas.drawCircle(
        p,
        r + px(6 + 4 * dash.value),
        Paint()
          ..color = Brand.swwYellow.withValues(alpha: 0.35 * (1 - dash.value)),
      );
    }
    canvas.drawCircle(p, r + px(2.5), Paint()..color = Colors.white);
    canvas.drawCircle(p, r, Paint()..color = Brand.swwYellow);
    final icon = switch (kind) {
      RouteStepKind.elevator => Icons.elevator_outlined,
      RouteStepKind.stairs => Icons.stairs_outlined,
      _ => Icons.escalator,
    };
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: r * 1.3,
          color: Brand.darkPage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
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
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = px(3),
    );
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
      // Move dashes forward along the route.
      var d = -(on + off) + (phase % (on + off));
      while (d < metric.length) {
        final a = math.max(0.0, d), b = math.min(metric.length, d + on);
        if (b > a) canvas.drawPath(metric.extractPath(a, b), paint);
        d += on + off;
      }
    }
  }

  @override
  bool shouldRepaint(MapOverlayPainter old) =>
      old.map != map ||
      old.selected != selected ||
      old.route != route ||
      old.currentStep != currentStep ||
      old.spot != spot;
}

/// The device position on the map: accuracy circle, heading cone and a blue
/// dot, eased between fixes. Repaints only itself (no relayout).
class LiveDotLayer extends StatefulWidget {
  const LiveDotLayer({
    super.key,
    required this.placement,
    required this.transform,
  });

  final ValueListenable<LivePlacement?> placement;
  final TransformationController transform;

  @override
  State<LiveDotLayer> createState() => _LiveDotLayerState();
}

class _LiveDotLayerState extends State<LiveDotLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _curve = CurvedAnimation(parent: _move, curve: Curves.easeInOut);
  LiveDot? _from;
  LiveDot? _to;

  @override
  void initState() {
    super.initState();
    widget.placement.addListener(_onFix);
    _to = LiveDot.of(widget.placement.value);
  }

  @override
  void didUpdateWidget(LiveDotLayer old) {
    super.didUpdateWidget(old);
    if (old.placement != widget.placement) {
      old.placement.removeListener(_onFix);
      widget.placement.addListener(_onFix);
      _onFix();
    }
  }

  void _onFix() {
    final next = LiveDot.of(widget.placement.value);
    final cur = current;
    // Jump on the first fix or from far away; glide otherwise.
    _from = cur != null && next != null && (cur.pos - next.pos).distance < 600
        ? cur
        : null;
    _to = next;
    // Runs even for a jump, so the layer repaints.
    _move.forward(from: 0);
  }

  /// The dot as drawn right now.
  LiveDot? get current {
    final to = _to, from = _from;
    if (to == null || from == null || _move.isCompleted) return to;
    return LiveDot.lerp(from, to, _curve.value);
  }

  @override
  void dispose() {
    widget.placement.removeListener(_onFix);
    _curve.dispose();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: LiveDotPainter(
      dot: () => current,
      repaint: Listenable.merge([widget.transform, _move]),
      transform: widget.transform,
    ),
  );
}

/// What [LiveDotPainter] draws, in image px.
@immutable
class LiveDot {
  const LiveDot(this.pos, this.radius, this.angle);
  final Offset pos;
  final double radius;
  final double? angle;

  static LiveDot? of(LivePlacement? p) =>
      p == null || p.offMap ? null : LiveDot(p.pos, p.radiusPx, p.angle);

  static LiveDot lerp(LiveDot a, LiveDot b, double t) {
    double? angle = b.angle;
    if (a.angle != null && b.angle != null) {
      // Turn the short way round.
      var d = (b.angle! - a.angle!) % (2 * math.pi);
      if (d > math.pi) d -= 2 * math.pi;
      angle = a.angle! + d * t;
    }
    return LiveDot(
      Offset.lerp(a.pos, b.pos, t)!,
      a.radius + (b.radius - a.radius) * t,
      angle,
    );
  }
}

/// Blue dot with a white ring, a translucent accuracy circle and a heading
/// cone. Sizes other than the accuracy circle stay constant on screen.
class LiveDotPainter extends CustomPainter {
  LiveDotPainter({
    required this.dot,
    required Listenable repaint,
    required this.transform,
  }) : super(repaint: repaint);

  final LiveDot? Function() dot;
  final TransformationController transform;

  @override
  void paint(Canvas canvas, Size size) {
    final d = dot();
    if (d == null) return;
    final m = transform.value.storage;
    final s = math.sqrt(m[0] * m[0] + m[1] * m[1]).clamp(0.01, 100.0);
    double px(double screen) => screen / s;

    final ring = px(10), core = px(7);
    if (d.radius > ring) {
      canvas.drawCircle(
        d.pos,
        d.radius,
        Paint()..color = Brand.neverBlue.withValues(alpha: 0.14),
      );
      canvas.drawCircle(
        d.pos,
        d.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = px(1.5)
          ..color = Brand.neverBlue.withValues(alpha: 0.45),
      );
    }
    final a = d.angle;
    if (a != null) {
      final r = px(48);
      const spread = math.pi / 5;
      final cone = Path()
        ..moveTo(d.pos.dx, d.pos.dy)
        ..arcTo(
          Rect.fromCircle(center: d.pos, radius: r),
          a - spread,
          spread * 2,
          false,
        )
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Brand.neverBlue.withValues(alpha: 0.55),
              Brand.neverBlue.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: d.pos, radius: r)),
      );
    }
    canvas.drawCircle(d.pos, ring, Paint()..color = Colors.white);
    canvas.drawCircle(d.pos, core, Paint()..color = Brand.neverBlue);
  }

  @override
  bool shouldRepaint(LiveDotPainter old) => old.transform != transform;
}

/// "Venue map: ..." credit line linking to the source.
Widget mapCredit(
  BuildContext context,
  OfficialMap map,
  void Function(String url) open,
) {
  final text = Theme.of(context).textTheme;
  return InkWell(
    onTap: () => open(map.sourceUrl),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        map.credit,
        textAlign: TextAlign.center,
        style: text.bodySmall?.copyWith(decoration: TextDecoration.underline),
      ),
    ),
  );
}
