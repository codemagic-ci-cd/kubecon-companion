import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/official_map.dart';
import '../location/live_location.dart';
import '../location/start_point.dart';
import '../services/location_service.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import '../widgets/official_map_view.dart';
import 'map_screen.dart';

/// Where a route starts.
class StartPoint {
  const StartPoint(
    this.nodeId,
    this.label, {
    this.icon = Icons.door_front_door_outlined,
    this.geo,
  });

  /// A start picked from a GPS fix.
  factory StartPoint.fromGeo(GeoStart g) => StartPoint(
    g.node.id,
    g.kind == GeoStartKind.indoor
        ? 'Near ${g.placeName}'
        : 'Via ${g.placeName}',
    icon: Icons.my_location,
    geo: g,
  );

  final String nodeId;
  final String label;
  final IconData icon;

  /// Set when the start came from the device location.
  final GeoStart? geo;

  /// GPS starts drop "From your location": the my_location icon says it and
  /// the place name must fit on a 375 px wide phone.
  String get chipLabel =>
      geo != null || label.startsWith('From ') ? label : 'From $label';

  /// Screen-reader text for the start chip.
  String get semanticLabel => geo == null
      ? chipLabel
      : 'From your location, ${geo!.kind == GeoStartKind.indoor ? 'near' : 'via'} ${geo!.placeName}';

  /// How the first step names the start ("From the 200 South entrance, ...").
  String get startName {
    if (geo != null) return 'the ${geo!.placeName}';
    return label.startsWith('From ') ? label.substring(5) : 'the $label';
  }
}

const _entrances = [
  StartPoint(OfficialMap.mainEntranceId, '200 South entrance'),
  StartPoint(OfficialMap.westTempleEntranceId, 'West Temple entrance'),
  StartPoint(
    OfficialMap.hyattLobbyId,
    'Hyatt lobby',
    icon: Icons.hotel_outlined,
  ),
];

IconData routeStepIcon(RouteStepKind k) => switch (k) {
  RouteStepKind.outdoor => Icons.near_me_outlined,
  RouteStepKind.walk => Icons.directions_walk,
  RouteStepKind.escalator => Icons.escalator,
  RouteStepKind.elevator => Icons.elevator_outlined,
  RouteStepKind.stairs => Icons.stairs_outlined,
  RouteStepKind.arrive => Icons.flag_outlined,
};

/// Interactive turn-by-turn directions drawn on the official venue map.
class MapDirections extends StatefulWidget {
  const MapDirections({
    super.key,
    required this.map,
    required this.room,
    required this.levelLabel,
    required this.locate,
    this.positions = locationStream,
    this.permitted = hasLocationPermission,
  });

  final OfficialMap map;
  final Room room;
  final String levelLabel;
  final LocationProvider locate;

  /// Live positions for the blue dot, used only once permission is granted.
  final LocationStreamProvider positions;
  final LocationPermissionCheck permitted;

  @override
  State<MapDirections> createState() => _MapDirectionsState();
}

class _MapDirectionsState extends State<MapDirections>
    with WidgetsBindingObserver {
  late final _live = LiveLocationController(
    map: widget.map,
    locate: widget.locate,
    positions: widget.positions,
  );
  final _mapKey = GlobalKey<OfficialMapViewState>();
  final _pages = PageController();
  StartPoint _start = _entrances.first;
  bool _stepFree = false;
  int _step = 0;
  MapRoute? _route;
  String? _toast;
  Timer? _toastTimer;
  bool _locating = false;

  /// Bumped whenever the start changes, so a late GPS fix is ignored.
  int _locateGen = 0;

  /// Why the automatic location attempt fell back to the main entrance.
  String? _locateNote;

  OfficialMap get _map => widget.map;
  MapRoom? get _geo => _map.room(widget.room.id, partOf: widget.room.partOf);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final picked = AppScope.read(context).directionsStart;
    if (picked != null && _map.node(picked.nodeId) != null) {
      _start = StartPoint(picked.nodeId, picked.label, icon: picked.icon);
    }
    _plan();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusStep(0);
      // No start picked by hand this session: show the route from the main
      // entrance right away and switch once a location fix arrives.
      if (picked == null) {
        _useLocation(explicit: false);
      } else {
        _showDotIfPermitted();
      }
    });
  }

  /// Shows the live dot when permission is already granted; never asks.
  Future<void> _showDotIfPermitted() async {
    var ok = false;
    try {
      ok = await widget.permitted();
    } catch (_) {}
    if (ok && mounted) _live.startStream();
  }

  bool _foreground = true;

  /// False while another route covers this one (tickers are muted then).
  bool _onScreen = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = TickerMode.valuesOf(context).enabled;
    if (on != _onScreen) {
      _onScreen = on;
      _syncLive();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncLive();
  }

  /// Runs the position stream only while this screen is showing and the app
  /// is in the foreground.
  void _syncLive() {
    if (_foreground && _onScreen) {
      _live.resume();
    } else {
      _live.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live.dispose();
    _toastTimer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _plan() {
    final door = _map.doorFor(widget.room.id, partOf: widget.room.partOf);
    _route = door == null
        ? null
        : RoutePlanner(_map).route(
            fromNodeId: _start.nodeId,
            toNodeId: door.id,
            destinationName: widget.room.name,
            destinationRect: _geo?.rect,
            startName: _start.startName,
            stepFree: _stepFree,
          );
    final g = _start.geo;
    if (_route != null && g != null && g.kind == GeoStartKind.nearby) {
      _route = _route!.withOutdoorLeg(
        RouteStep(
          kind: RouteStepKind.outdoor,
          title:
              'Walk to the ${g.placeName} (about ${g.outdoorMetresRounded} m, ${g.outdoorMinutes} min)',
          hint: 'Outdoors. Maps has the street route.',
          points: [g.node.pos],
          regionId: g.node.regionId,
          metres: g.outdoorMetres,
          mapsUrl: walkingDirectionsUrl(g.node),
        ),
      );
    }
    _step = 0;
  }

  /// A start picked by hand: use it and remember it for this app session.
  void _pick(StartPoint p) {
    _locateGen++;
    _locating = false;
    _locateNote = null;
    _start = p;
    AppScope.read(context).directionsStart = DirectionsStart(
      nodeId: p.nodeId,
      label: p.label,
      icon: p.icon,
    );
    _replan();
  }

  void _replan() {
    setState(_plan);
    if (_pages.hasClients) _pages.jumpToPage(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep(0));
  }

  Rect _stepRect(RouteStep st) {
    if (st.isLevelChange) {
      return Rect.fromCenter(center: st.points.last, width: 420, height: 360);
    }
    var r = Rect.fromPoints(st.points.first, st.points.first);
    for (final p in st.points) {
      r = r.expandToInclude(Rect.fromCenter(center: p, width: 1, height: 1));
    }
    if (st.kind == RouteStepKind.arrive && _geo != null) {
      r = r.expandToInclude(_geo!.rect);
    }
    final grow = math.max(0.0, 280 - math.min(r.width, r.height)) / 2;
    return r.inflate(60 + grow);
  }

  void _focusStep(int i, {String? fromRegion}) {
    final rt = _route;
    if (rt == null || i < 0 || i >= rt.steps.length) return;
    final st = rt.steps[i];
    _mapKey.currentState?.animateTo(_stepRect(st));
    if (fromRegion != null && fromRegion != st.regionId) {
      _showToast(_map.levelLabel(st.regionId));
    }
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _onPage(int i) {
    final rt = _route;
    if (rt == null) return;
    final prev = rt.steps[_step];
    final from = prev.regionId;
    setState(() => _step = i);
    _focusStep(i, fromRegion: from);
  }

  void _goTo(int i) => _pages.animateToPage(
    i,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
  );

  StartPoint? _currentSessionStart() {
    final app = AppScope.read(context);
    final now = app.now;
    Session? best;
    for (final s in app.savedSessions) {
      final live =
          !now.isBefore(s.start.subtract(const Duration(minutes: 10))) &&
          now.isBefore(s.end);
      final justEnded =
          !now.isBefore(s.end) &&
          now.difference(s.end) < const Duration(minutes: 45);
      if (!live && !justEnded) continue;
      if (best == null || s.start.isAfter(best.start)) best = s;
    }
    if (best == null) return null;
    final room = app.data.venue.room(best.roomId);
    if (room == null || room.id == widget.room.id) return null;
    final door = _map.doorFor(room.id, partOf: room.partOf);
    if (door == null) return null;
    return StartPoint(
      door.id,
      'From ${room.name}',
      icon: Icons.event_seat_outlined,
    );
  }

  Future<void> _pickStart() async {
    final app = AppScope.read(context);
    final current = _currentSessionStart();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Start from',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            for (final e in _entrances)
              if (_map.node(e.nodeId) != null)
                ListTile(
                  leading: Icon(e.icon),
                  title: Text(e.label),
                  selected: _start.nodeId == e.nodeId,
                  onTap: () => Navigator.pop(ctx, e),
                ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Use my location'),
              subtitle: const Text(
                'Nearest spot inside, or the closest entrance if you are outside',
              ),
              onTap: () => Navigator.pop(ctx, 'locate'),
            ),
            ListTile(
              leading: const Icon(Icons.event_seat_outlined),
              title: const Text('From my current session'),
              subtitle: Text(
                current == null
                    ? 'No saved session right now'
                    : current.label.substring(5),
              ),
              enabled: current != null,
              onTap: () => Navigator.pop(ctx, current),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Another room'),
              onTap: () => Navigator.pop(ctx, 'room'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is StartPoint) {
      _pick(choice);
    } else if (choice == 'locate') {
      AppScope.read(context).directionsStart = null;
      await _useLocation(explicit: true);
    } else if (choice == 'room') {
      final room = await showSearch<Room?>(
        context: context,
        delegate: RoomSearchDelegate(app.data.venue, label: 'Start from room'),
      );
      if (room == null || !mounted) return;
      final door = _map.doorFor(room.id, partOf: room.partOf);
      if (door == null) {
        _snack('${room.name} is not on the map yet.');
        return;
      }
      _pick(
        StartPoint(
          door.id,
          'From ${room.name}',
          icon: Icons.meeting_room_outlined,
        ),
      );
    }
  }

  void _snack(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  /// Tries the device location and switches the start when a usable fix
  /// arrives. [explicit] is a tap on "Use my location": failures then show a
  /// message; the automatic attempt on open fails quietly.
  Future<void> _useLocation({required bool explicit}) async {
    final gen = ++_locateGen;
    setState(() {
      _locating = true;
      _locateNote = null;
    });
    LocationResult res;
    try {
      res = await widget.locate();
    } catch (_) {
      res = const LocationFailure(
        'Could not get your location. Pick a start point instead.',
      );
    }
    if (!mounted) return;
    // A fix means permission is granted: show the live dot.
    if (res is LocationFix) _live.startStream(res);
    if (gen != _locateGen) return;
    final g = switch (res) {
      LocationFix f => chooseGeoStart(
        _map,
        lat: f.lat,
        lng: f.lng,
        accuracy: f.accuracy,
      ),
      LocationFailure _ => chooseGeoStart(_map),
    };
    if (g.kind != GeoStartKind.fallback) {
      _locating = false;
      _start = StartPoint.fromGeo(g);
      _replan();
      return;
    }
    final message = switch (g.reason) {
      GeoFallbackReason.tooFar =>
        'You are more than ${GeoStartRules.maxOutdoorMetres ~/ 1000} km from the venue, so directions start at the 200 South entrance.',
      GeoFallbackReason.inaccurate => 'Your location is too imprecise right now, so directions start at the 200 South entrance.',
      _ => res is LocationFailure ? res.message : 'Location is unavailable.',
    };
    final reset = _start.geo != null || (explicit && res is LocationFix);
    setState(() {
      _locating = false;
      _locateNote = explicit
          ? null
          : switch (g.reason) {
              GeoFallbackReason.tooFar => 'You are not near the venue yet.',
              GeoFallbackReason.inaccurate => 'Location is too imprecise.',
              _ => '',
            };
      if (reset) {
        _start = _entrances.first;
        _plan();
      }
    });
    if (explicit) _snack(message);
    if (reset) {
      if (_pages.hasClients) _pages.jumpToPage(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep(0));
    }
  }

  /// One subtle line under the start chip: the floor caveat for indoor GPS
  /// starts, or a way to retry location after a quiet failure.
  Widget _startNote(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (_start.geo?.kind == GeoStartKind.indoor) {
      return InkWell(
        onTap: _pickStart,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            "Indoor GPS can't tell floors — tap to change",
            style: style,
          ),
        ),
      );
    }
    final note = _locateNote;
    if (note == null || _locating || _start.geo != null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        if (note.isNotEmpty)
          Flexible(
            child: Text(note, style: style, overflow: TextOverflow.ellipsis),
          ),
        TextButton.icon(
          onPressed: () => _useLocation(explicit: true),
          icon: const Icon(Icons.my_location, size: 16),
          label: const Text('Use my location'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: style?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rt = _route;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white,
                  child: OfficialMapView(
                    key: _mapKey,
                    map: _map,
                    selectedRoomId: _geo?.id,
                    route: rt,
                    currentStep: _step,
                    liveLocation: _live.placement,
                    initialFocus: rt == null ? null : _stepRect(rt.steps.first),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: MapIconButton(
                  tooltip: 'Show whole map',
                  icon: Icons.fit_screen_outlined,
                  onPressed: () => _mapKey.currentState?.fit(),
                ),
              ),
              if (rt != null)
                Positioned(
                  left: 12,
                  top: 12,
                  child: Tooltip(
                    message: 'An estimate: the venue map is not to scale. Follow onsite signage.',
                    child: Pill(
                      rt.walkLabel,
                      icon: Icons.directions_walk,
                      color: Brand.neverBlue,
                    ),
                  ),
                ),
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _toast == null
                          ? const SizedBox.shrink()
                          : Container(
                              key: ValueKey(_toast),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Brand.swwYellow,
                                borderRadius: BorderRadius.circular(
                                  Brand.radiusPill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.swap_vert,
                                    size: 18,
                                    color: Brand.darkPage,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _toast!,
                                    style: text.labelLarge?.copyWith(
                                      color: Brand.darkPage,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: ActionChip(
                          avatar: _locating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(_start.icon, size: 18),
                          label: Text(
                            _start.chipLabel,
                            semanticsLabel: _start.semanticLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                          tooltip: 'Change start point',
                          onPressed: _pickStart,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.accessible, size: 18),
                        label: const Text('Step-free'),
                        tooltip:
                            'Prefer elevators, avoid escalators and stairs',
                        selected: _stepFree,
                        showCheckmark: false,
                        onSelected: (v) {
                          _stepFree = v;
                          _replan();
                        },
                      ),
                    ],
                  ),
                  _startNote(context),
                  const SizedBox(height: 8),
                  if (rt == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No route found from here. Try another start point or ask at any Info Desk.',
                        style: text.bodyMedium,
                      ),
                    )
                  else ...[
                    SizedBox(
                      height: 176,
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: rt.steps.length,
                        onPageChanged: _onPage,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _StepCard(
                            step: rt.steps[i],
                            index: i,
                            count: rt.steps.length,
                            onOpenMaps: (url) => openLink(context, url),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous step',
                          onPressed: _step > 0 ? () => _goTo(_step - 1) : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: _Dots(
                            count: rt.steps.length,
                            index: _step,
                            steps: rt.steps,
                            onTap: _goTo,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next step',
                          onPressed: _step < rt.steps.length - 1
                              ? () => _goTo(_step + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                  mapCredit(context, _map, (url) => openLink(context, url)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.index,
    required this.count,
    required this.onOpenMaps,
  });
  final RouteStep step;
  final int index;
  final int count;
  final ValueChanged<String> onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final change = step.isLevelChange;
    final arrive = step.kind == RouteStepKind.arrive;
    final badge = change
        ? Brand.swwYellow
        : (arrive ? Brand.neverBlue : b.subtle);
    final badgeFg = change
        ? Brand.darkPage
        : (arrive ? Colors.white : b.heading);
    return BrandCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
            child: Icon(routeStepIcon(step.kind), color: badgeFg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step ${index + 1} of $count',
                  style: text.bodySmall?.copyWith(
                    color: change ? Brand.swwYellow : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.title,
                  style: text.titleSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (step.hint != null) ...[
                  const SizedBox(height: 4),
                  Expanded(
                    child: _HintText(step.hint!, style: text.bodyMedium),
                  ),
                ],
                if (step.mapsUrl != null) ...[
                  const SizedBox(height: 8),
                  SubtleButton(
                    icon: Icons.open_in_new,
                    label: 'Open in maps',
                    onPressed: () => onOpenMaps(step.mapsUrl!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable hint with a visible thumb, so long landmark hints are not
/// silently cut off on small phones.
class _HintText extends StatefulWidget {
  const _HintText(this.hint, {this.style});
  final String hint;
  final TextStyle? style;

  @override
  State<_HintText> createState() => _HintTextState();
}

class _HintTextState extends State<_HintText> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.only(right: 8),
      child: Text(widget.hint, style: widget.style),
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.steps,
    required this.onTap,
  });
  final int count;
  final int index;
  final List<RouteStep> steps;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index
                    ? (steps[i].isLevelChange
                          ? Brand.swwYellow
                          : Brand.neverBlue)
                    : (steps[i].isLevelChange
                          ? Brand.swwYellow.withValues(alpha: 0.5)
                          : b.body.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(Brand.radiusPill),
              ),
            ),
          ),
      ],
    );
  }
}
