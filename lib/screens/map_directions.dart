import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/official_map.dart';
import '../services/location_service.dart';
import '../state/app_scope.dart';
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
  });
  final String nodeId;
  final String label;
  final IconData icon;
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
  });

  final OfficialMap map;
  final Room room;
  final String levelLabel;
  final LocationProvider locate;

  @override
  State<MapDirections> createState() => _MapDirectionsState();
}

class _MapDirectionsState extends State<MapDirections> {
  final _mapKey = GlobalKey<OfficialMapViewState>();
  final _pages = PageController();
  StartPoint _start = _entrances.first;
  bool _stepFree = false;
  int _step = 0;
  MapRoute? _route;
  String? _toast;
  Timer? _toastTimer;
  bool _locating = false;

  OfficialMap get _map => widget.map;
  MapRoom? get _geo => _map.room(widget.room.id, partOf: widget.room.partOf);

  @override
  void initState() {
    super.initState();
    _plan();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep(0));
  }

  @override
  void dispose() {
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
            startName: _start.label.startsWith('From ')
                ? _start.label.substring(5)
                : 'the ${_start.label}',
            stepFree: _stepFree,
          );
    _step = 0;
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
              subtitle: const Text('Picks the nearest entrance'),
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
      _start = choice;
      _replan();
    } else if (choice == 'locate') {
      await _useLocation();
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
      _start = StartPoint(
        door.id,
        'From ${room.name}',
        icon: Icons.meeting_room_outlined,
      );
      _replan();
    }
  }

  void _snack(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    final res = await widget.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    switch (res) {
      case LocationFailure f:
        _snack(f.message);
      case LocationFix fix:
        final near = nearestGeoNode(_map, fix.lat, fix.lng);
        if (near == null) {
          _snack('Could not match your location to the venue.');
          return;
        }
        final (node, dist) = near;
        if (dist > 1500) {
          _snack(
            'You seem to be ${(dist / 1000).toStringAsFixed(1)} km from the venue. Starting at the closest entrance.',
          );
        } else {
          _snack(
            'Starting at the nearest entrance. Indoor GPS is approximate, so check the signs around you.',
          );
        }
        _start = StartPoint(
          node.id,
          node.label ?? 'Nearest entrance',
          icon: Icons.my_location,
        );
        _replan();
    }
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
                      '~${rt.minutes} min walk',
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
                            _start.label.startsWith('From ')
                                ? _start.label
                                : 'From ${_start.label}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          tooltip: 'Change start point',
                          onPressed: _locating ? null : _pickStart,
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
  });
  final RouteStep step;
  final int index;
  final int count;

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
