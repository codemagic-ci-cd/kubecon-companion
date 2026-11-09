import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../data/official_map.dart';
import '../services/location_service.dart';
import 'geo_projection.dart';
import 'start_point.dart';

/// A GPS fix placed on the venue map image.
class LivePlacement {
  const LivePlacement({
    required this.fix,
    required this.pos,
    required this.radiusPx,
    required this.offMap,
    required this.metresAway,
    this.angle,
    this.near,
  });

  final LocationFix fix;

  /// Image px on the main Salt Palace plan.
  final Offset pos;

  /// Accuracy circle radius in image px.
  final double radiusPx;

  /// Heading as an image angle (radians), when the device knows it.
  final double? angle;

  /// More than [GeoProjection.offMapMetres] outside the building outline.
  final bool offMap;

  /// Metres from the building outline (0 inside).
  final double metresAway;

  /// Nearest geo-anchored place on the ground floor.
  final MapNode? near;

  int get accuracyMetres => fix.accuracy.round();

  /// "about 450 m" / "about 2.3 km" from the venue.
  String get awayLabel {
    if (metresAway >= 1000) {
      return '${(metresAway / 1000).toStringAsFixed(1)} km';
    }
    final m = ((metresAway / 10).round() * 10).clamp(10, 990);
    return '$m m';
  }
}

/// Places [fix] on [map]; null when the map has no geo calibration.
LivePlacement? placeFix(OfficialMap map, LocationFix fix) {
  final proj = GeoProjection.of(map);
  if (proj == null) return null;
  final away = distanceToFootprint(map, fix.lat, fix.lng);
  final offMap = away > GeoProjection.offMapMetres;
  final ground = groundAnchors(map).toSet();
  final near = offMap
      ? null
      : nearestGeoNode(map, fix.lat, fix.lng, where: ground.contains)?.$1;
  final h = fix.heading;
  return LivePlacement(
    fix: fix,
    pos: proj.toImage(fix.lat, fix.lng),
    radiusPx: fix.accuracy * proj.pxPerMetre,
    angle: h == null ? null : proj.imageAngle(h),
    offMap: offMap,
    metresAway: away,
    near: near,
  );
}

enum LiveStatus {
  /// Not tracking.
  off,

  /// Asking for permission / the first fix.
  starting,

  /// Stream running.
  live,

  /// Permission denied or location unavailable.
  unavailable,
}

/// Live location on the venue map: permission + first fix, the position
/// stream, follow mode and pausing while hidden.
class LiveLocationController extends ChangeNotifier {
  LiveLocationController({
    required this.map,
    required this.locate,
    required this.positions,
  });

  final OfficialMap map;
  final LocationProvider locate;
  final LocationStreamProvider positions;

  /// The latest placed fix; the dot layer listens to this.
  final placement = ValueNotifier<LivePlacement?>(null);

  LiveStatus _status = LiveStatus.off;
  LiveStatus get status => _status;

  String? _error;

  /// Why location is unavailable.
  String? get error => _error;

  bool _follow = false;

  /// The camera keeps the dot centred.
  bool get follow => _follow;

  /// Tracking was on when [pause] stopped it.
  bool _resumeWanted = false;
  bool _paused = false;
  bool _disposed = false;
  int _gen = 0;
  StreamSubscription<LocationFix>? _sub;

  /// Whether a position stream is subscribed right now.
  bool get streaming => _sub != null;

  /// Called for every new placement while [follow] is on.
  VoidCallback? onFollowFix;

  /// The "Locate me" tap: starts tracking, or turns follow back on.
  Future<void> locateMe() async {
    if (_status == LiveStatus.live || _status == LiveStatus.starting) {
      _follow = true;
      notifyListeners();
      if (placement.value != null) onFollowFix?.call();
      return;
    }
    await _start();
  }

  /// Starts the stream without asking for permission (use only once it is
  /// known to be granted).
  void startStream([LocationFix? first]) {
    if (_disposed) return;
    if (first != null) _set(first);
    if (_sub != null) return;
    _status = LiveStatus.live;
    _resumeWanted = true;
    if (!_paused) _listen();
    notifyListeners();
  }

  Future<void> _start() async {
    final gen = ++_gen;
    _status = LiveStatus.starting;
    _error = null;
    _follow = true;
    notifyListeners();
    LocationResult res;
    try {
      res = await locate();
    } catch (_) {
      res = const LocationFailure('Could not get your location.');
    }
    if (_disposed || gen != _gen) return;
    switch (res) {
      case LocationFix f:
        _status = LiveStatus.live;
        _resumeWanted = true;
        _set(f);
        if (!_paused) _listen();
      case LocationFailure f:
        _status = LiveStatus.unavailable;
        _error = _reason(f.message);
        _follow = false;
    }
    notifyListeners();
  }

  /// Failure messages from the location service end with advice for the
  /// directions screens; on the map only the reason matters.
  static String _reason(String m) =>
      m.replaceFirst(RegExp(r'\s*Pick a start point instead\.?$'), '');

  void _listen() {
    _sub?.cancel();
    _sub = positions().listen(_set, onError: (Object _) {});
  }

  void _set(LocationFix f) {
    final p = placeFix(map, f);
    placement.value = p;
    if (_follow && p != null && !p.offMap) onFollowFix?.call();
    notifyListeners();
  }

  /// The user moved the camera: stop following.
  void userMoved() {
    if (!_follow) return;
    _follow = false;
    notifyListeners();
  }

  /// Stops the stream (tab hidden, app backgrounded); [resume] restarts it
  /// if it was running.
  void pause() {
    if (_paused) return;
    _paused = true;
    _gen++;
    if (_status == LiveStatus.starting) _status = LiveStatus.off;
    _stopStream();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_resumeWanted && !_disposed) {
      _status = LiveStatus.live;
      _listen();
      notifyListeners();
    }
  }

  /// Turns tracking off entirely.
  void stop() {
    _gen++;
    _resumeWanted = false;
    _follow = false;
    _status = LiveStatus.off;
    _stopStream();
    placement.value = null;
    notifyListeners();
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopStream();
    placement.dispose();
    super.dispose();
  }
}
