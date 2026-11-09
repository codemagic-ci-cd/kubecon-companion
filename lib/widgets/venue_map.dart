import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../theme/brand.dart';

/// Schematic coordinate space used by venue.json (per level).
const mapWidth = 1000.0;
const mapHeight = 600.0;

IconData landmarkIcon(String kind) => switch (kind) {
  'entrance' => Icons.door_front_door_outlined,
  'registration' => Icons.badge_outlined,
  'escalator' => Icons.escalator,
  'elevator' => Icons.elevator_outlined,
  'stairs' => Icons.stairs_outlined,
  'restroom' => Icons.wc,
  'food' => Icons.restaurant,
  'info' => Icons.info_outline,
  'expo' => Icons.storefront_outlined,
  'keynote' => Icons.mic_none,
  _ => Icons.place_outlined,
};

Color landmarkColor(String kind) => switch (kind) {
  'food' => Brand.nativeOrange,
  'escalator' || 'elevator' || 'stairs' => Brand.swwYellow,
  _ => Brand.dashAqua,
};

/// "Room 251 A-C (Workshops)" -> "251 A-C".
String shortRoomLabel(String name) {
  var s = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  s = s.replaceFirst(RegExp(r'^Room\s+', caseSensitive: false), '');
  return s.isEmpty ? name : s;
}

/// Maps venue coordinates to canvas coordinates, cropped to [bounds] (the
/// part of the level that has content). In portrait the plan is rotated so
/// north points up, which also fits a phone screen far better.
class MapProjection {
  const MapProjection({
    required this.northUp,
    this.bounds = const Rect.fromLTWH(0, 0, mapWidth, mapHeight),
  });
  final bool northUp;
  final Rect bounds;

  Size get canvasSize =>
      northUp ? Size(bounds.height, bounds.width) : bounds.size;

  Offset toCanvas(Offset p) => northUp
      ? Offset(p.dy - bounds.top, bounds.right - p.dx)
      : p - bounds.topLeft;

  Offset toMap(Offset c) => northUp
      ? Offset(bounds.right - c.dy, c.dx + bounds.top)
      : c + bounds.topLeft;

  Rect rectToCanvas(double x, double y, double w, double h) => northUp
      ? Rect.fromLTWH(y - bounds.top, bounds.right - x - w, h, w)
      : Rect.fromLTWH(x - bounds.left, y - bounds.top, w, h);
}

/// Area of a level that has rooms or landmarks, with a margin.
Rect levelBounds(
  Venue venue,
  String levelId, [
  List<RouteLeg> route = const [],
]) {
  Rect? b;
  void add(Rect r) => b = b == null ? r : b!.expandToInclude(r);
  for (final r in venue.roomsOn(levelId)) {
    add(Rect.fromLTWH(r.x, r.y, r.w, r.h));
  }
  for (final l in venue.landmarksOn(levelId)) {
    add(Rect.fromCircle(center: Offset(l.x, l.y), radius: 12));
  }
  for (final leg in route.where((l) => l.levelId == levelId)) {
    add(Rect.fromPoints(leg.from, leg.to));
  }
  if (b == null) return const Rect.fromLTWH(0, 0, mapWidth, mapHeight);
  return b!.inflate(24);
}

class VenueMapPainter extends CustomPainter {
  VenueMapPainter({
    required this.rooms,
    required this.landmarks,
    required this.projection,
    required this.surfaces,
    required this.scale,
    this.highlightRoomId,
    this.route = const [],
    this.selectedLandmarkId,
  });

  final List<Room> rooms;
  final List<Landmark> landmarks;
  final MapProjection projection;
  final BrandSurfaces surfaces;
  final double scale;
  final String? highlightRoomId;
  final List<RouteLeg> route;
  final String? selectedLandmarkId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    final dark = surfaces.isDark;

    // Floor plate: bounding box of everything on this level.
    if (rooms.isNotEmpty || landmarks.isNotEmpty) {
      Rect? bounds;
      for (final r in rooms) {
        final rr = projection.rectToCanvas(r.x, r.y, r.w, r.h);
        bounds = bounds == null ? rr : bounds.expandToInclude(rr);
      }
      for (final l in landmarks) {
        final p = projection.toCanvas(Offset(l.x, l.y));
        final lr = Rect.fromCircle(center: p, radius: 12);
        bounds = bounds == null ? lr : bounds.expandToInclude(lr);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds!.inflate(14), const Radius.circular(20)),
        Paint()
          ..color = dark ? const Color(0xFF0A1428) : const Color(0xFFF8FAFD),
      );
    }

    final fill = Paint()..color = surfaces.cardFill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = dark ? const Color(0x33FFFFFF) : const Color(0x2611285B);
    final hiFill = Paint()..color = Brand.neverBlue;

    for (final r in rooms) {
      final rect = projection.rectToCanvas(r.x, r.y, r.w, r.h);
      final rr = RRect.fromRectAndRadius(
        rect.deflate(1.5),
        Radius.circular(math.min(8, math.min(rect.width, rect.height) / 4)),
      );
      final hi = r.id == highlightRoomId;
      canvas.drawRRect(rr, hi ? hiFill : fill);
      canvas.drawRRect(rr, stroke);
      _label(
        canvas,
        r.partOf != null || r.w * r.h < 2500 ? shortRoomLabel(r.name) : r.name,
        rect.deflate(3),
        hi ? Colors.white : surfaces.heading,
        bold: hi,
      );
    }

    // Route legs (dashed orange L-shapes).
    final routePaint = Paint()
      ..color = Brand.swwYellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final leg in route) {
      // Elbow in venue space (along the corridor first), then project.
      final pts = elbowPath(leg.from, leg.to).map(projection.toCanvas).toList();
      for (var i = 1; i < pts.length; i++) {
        _dashed(canvas, pts[i - 1], pts[i], routePaint);
      }
      canvas.drawCircle(pts.first, 7, Paint()..color = Brand.swwYellow);
      canvas.drawCircle(pts.first, 3, Paint()..color = Colors.white);
    }

    for (final l in landmarks) {
      final p = projection.toCanvas(Offset(l.x, l.y));
      final selected = l.id == selectedLandmarkId;
      final radius = selected ? 13.0 : 10.0;
      canvas.drawCircle(
        p,
        radius + 2,
        Paint()..color = dark ? Brand.darkPage : Colors.white,
      );
      canvas.drawCircle(p, radius, Paint()..color = landmarkColor(l.kind));
      _icon(canvas, landmarkIcon(l.kind), p, radius * 1.3, Brand.darkPage);
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 10.0, gap = 7.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  void _icon(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(
    Canvas canvas,
    String text,
    Rect rect,
    Color color, {
    bool bold = false,
  }) {
    if (rect.width < 6 || rect.height < 5) return;
    var fontSize = math.min(
      15.0,
      math.max(5.0, math.min(rect.width, rect.height) / 3.2),
    );
    TextPainter? tp;
    for (var i = 0; i < 6; i++) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: fontSize,
            height: 1.15,
            letterSpacing: -0.2,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: rect.width);
      if (tp.height <= rect.height && !tp.didExceedMaxLines) break;
      if (fontSize <= 5) break;
      fontSize = math.max(5, fontSize * 0.82);
    }
    canvas.save();
    canvas.clipRect(rect);
    tp!.paint(
      canvas,
      Offset(
        rect.left + (rect.width - tp.width) / 2,
        rect.top + (rect.height - tp.height) / 2,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(VenueMapPainter old) =>
      old.rooms != rooms ||
      old.highlightRoomId != highlightRoomId ||
      old.route != route ||
      old.scale != scale ||
      old.surfaces != surfaces ||
      old.projection.northUp != projection.northUp ||
      old.selectedLandmarkId != selectedLandmarkId;
}

/// Pinch-zoomable schematic of one level.
class VenueMapView extends StatefulWidget {
  const VenueMapView({
    super.key,
    required this.venue,
    required this.levelId,
    this.highlightRoomId,
    this.route = const [],
    this.onRoomTap,
    this.onLandmarkTap,
    this.interactive = true,
    this.focusOnHighlight = true,
  });

  final Venue venue;
  final String levelId;
  final String? highlightRoomId;
  final List<RouteLeg> route;
  final ValueChanged<Room>? onRoomTap;
  final ValueChanged<Landmark>? onLandmarkTap;
  final bool interactive;
  final bool focusOnHighlight;

  @override
  State<VenueMapView> createState() => VenueMapViewState();
}

class VenueMapViewState extends State<VenueMapView> {
  final _controller = TransformationController();
  Size? _viewport;
  String? _focusedKey;
  String? _selectedLandmark;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void resetView() {
    _controller.value = Matrix4.identity();
  }

  MapProjection _projectionFor(Size viewport) => MapProjection(
    northUp: viewport.height > viewport.width * 0.95,
    bounds: levelBounds(widget.venue, widget.levelId, widget.route),
  );

  double _fit(Size viewport, MapProjection p) => math.min(
    viewport.width / p.canvasSize.width,
    viewport.height / p.canvasSize.height,
  );

  Offset _origin(Size viewport, MapProjection p, double fit) => Offset(
    (viewport.width - p.canvasSize.width * fit) / 2,
    (viewport.height - p.canvasSize.height * fit) / 2,
  );

  void _maybeFocus(Size viewport) {
    final room = widget.venue.room(widget.highlightRoomId);
    final key = '${widget.levelId}|${room?.id}|$viewport';
    if (!widget.focusOnHighlight || _focusedKey == key) return;
    _focusedKey = key;
    if (room == null || room.levelId != widget.levelId) {
      _controller.value = Matrix4.identity();
      return;
    }
    final p = _projectionFor(viewport);
    final fit = _fit(viewport, p);
    final rect = p.rectToCanvas(room.x, room.y, room.w, room.h);
    final o = _origin(viewport, p, fit);
    final center = o + rect.center * fit;
    // Zoom just enough that a small room becomes comfortably tappable.
    final minSide = math.min(rect.width, rect.height) * fit;
    final s = (52 / math.max(minSide, 1)).clamp(1.0, 3.0);
    if (s <= 1.0) {
      _controller.value = Matrix4.identity();
      return;
    }
    final tx = viewport.width / 2 - s * center.dx;
    final ty = viewport.height / 2 - s * center.dy;
    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  void _handleTap(Offset local, MapProjection p, double fit) {
    final canvasPt = local / fit;
    final mapPt = p.toMap(canvasPt);
    final touchRadius = 16 / (fit * _controller.value.getMaxScaleOnAxis());
    for (final l in widget.venue.landmarksOn(widget.levelId).reversed) {
      if ((Offset(l.x, l.y) - mapPt).distance <= math.max(12, touchRadius)) {
        setState(() => _selectedLandmark = l.id);
        widget.onLandmarkTap?.call(l);
        return;
      }
    }
    for (final r in widget.venue.roomsOn(widget.levelId).reversed) {
      if (r.contains(mapPt.dx, mapPt.dy)) {
        setState(() => _selectedLandmark = null);
        widget.onRoomTap?.call(r);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final p = _projectionFor(viewport);
        final fit = _fit(viewport, p);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeFocus(viewport);
        });
        _viewport = viewport;

        final canvas = SizedBox(
          width: p.canvasSize.width * fit,
          height: p.canvasSize.height * fit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: widget.interactive
                ? (d) => _handleTap(d.localPosition, p, fit)
                : null,
            child: CustomPaint(
              painter: VenueMapPainter(
                rooms: widget.venue.roomsOn(widget.levelId),
                landmarks: widget.venue.landmarksOn(widget.levelId),
                projection: p,
                surfaces: surfaces,
                scale: fit,
                highlightRoomId: widget.highlightRoomId,
                route: widget.route
                    .where((l) => l.levelId == widget.levelId)
                    .toList(),
                selectedLandmarkId: _selectedLandmark,
              ),
            ),
          ),
        );

        final content = SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: Center(child: canvas),
        );

        return ClipRect(
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 1,
            maxScale: 8,
            panEnabled: widget.interactive,
            scaleEnabled: widget.interactive,
            boundaryMargin: const EdgeInsets.all(48),
            child: content,
          ),
        );
      },
    );
  }

  Size? get viewport => _viewport;
}
