import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../outdoor/outdoor_loader.dart';
import '../outdoor/outdoor_map.dart';
import '../outdoor/outdoor_nav.dart';
import '../outdoor/outdoor_steps.dart';
import '../services/location_service.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import '../widgets/outdoor_map_view.dart';
import 'map_screen.dart' show MapIconButton;
import 'directions_screen.dart' show StepList;

const _osmCopyright = 'https://www.openstreetmap.org/copyright';

/// Venue name without the "(Floor 2, Paris Ballroom)" detail.
String shortVenueName(String name) {
  final i = name.indexOf(' (');
  return i > 0 ? name.substring(0, i) : name;
}

IconData outdoorStepIcon(OutdoorStep s) => switch (s.kind) {
  OutdoorStepKind.depart => Icons.directions_walk,
  OutdoorStepKind.cross => Icons.traffic_outlined,
  OutdoorStepKind.arrive => Icons.flag_outlined,
  OutdoorStepKind.turn => switch (s.turn) {
    TurnDirection.straight => Icons.straight,
    TurnDirection.slightLeft => Icons.turn_slight_left,
    TurnDirection.left => Icons.turn_left,
    TurnDirection.sharpLeft => Icons.turn_sharp_left,
    TurnDirection.slightRight => Icons.turn_slight_right,
    TurnDirection.right => Icons.turn_right,
    TurnDirection.sharpRight => Icons.turn_sharp_right,
  },
};

/// Directions to an off-site venue: interactive on our own street map when
/// the map covers it, otherwise the written steps.
class OffsiteDirections extends StatefulWidget {
  const OffsiteDirections({
    super.key,
    required this.venue,
    required this.locate,
    this.positions = locationStream,
    this.loader = loadOutdoorMap,
  });

  final OffsiteVenue venue;
  final LocationProvider locate;
  final LocationStreamProvider positions;
  final OutdoorLoader loader;

  @override
  State<OffsiteDirections> createState() => _OffsiteDirectionsState();
}

class _OffsiteDirectionsState extends State<OffsiteDirections> {
  Future<OutdoorMap?>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= widget.loader(DefaultAssetBundle.of(context));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OutdoorMap?>(
    future: _load,
    builder: (context, snap) {
      final map = snap.data;
      final v = widget.venue;
      final target = map == null
          ? null
          : resolveTarget(
              map,
              id: v.id,
              name: shortVenueName(v.name),
              fullName: v.name,
              lat: v.lat,
              lng: v.lng,
            );
      if (map != null && target != null) {
        return OutdoorDirections(
          map: map,
          target: target,
          venue: v,
          locate: widget.locate,
          positions: widget.positions,
        );
      }
      return OffsiteTextDirections(
        venue: v,
        loading: snap.connectionState != ConnectionState.done,
      );
    },
  );
}

String _mapsUrl(OffsiteVenue venue) {
  final query = venue.lat != null && venue.lng != null
      ? '${venue.lat},${venue.lng}'
      : (venue.address ?? venue.name);
  return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
}

const _badgeNote =
    'Walking times are estimates. Bring your badge: you need it to get back into the venue.';

List<DirectionStep> _writtenSteps(OffsiteVenue venue) {
  final raw = venue.directions.isEmpty
      ? ['Exit the Salt Palace and follow the address below']
      : venue.directions;
  return [
    for (var i = 0; i < raw.length; i++)
      DirectionStep(
        raw[i],
        i == 0
            ? StepKind.start
            : (i == raw.length - 1 ? StepKind.arrive : StepKind.walk),
      ),
  ];
}

/// Text-only off-site directions (no street map for this venue, or it is
/// still loading).
class OffsiteTextDirections extends StatelessWidget {
  const OffsiteTextDirections({
    super.key,
    required this.venue,
    this.loading = false,
  });
  final OffsiteVenue venue;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _VenueHeader(
          venue: venue,
          walkLabel: venue.walkMinutes == null
              ? null
              : '${venue.walkMinutes} min walk',
          startLabel: 'From the 200 South entrance',
        ),
        if (loading) ...[
          const SizedBox(height: 12),
          Text('Loading the street map…', style: text.bodySmall),
        ],
        const SizedBox(height: 20),
        StepList(steps: _writtenSteps(venue)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SubtleButton(
            icon: Icons.open_in_new,
            label: 'Open in maps',
            onPressed: () => openLink(context, _mapsUrl(venue)),
          ),
        ),
        const SizedBox(height: 12),
        Text(_badgeNote, style: text.bodySmall),
      ],
    );
  }
}

class _VenueHeader extends StatelessWidget {
  const _VenueHeader({
    required this.venue,
    this.walkLabel,
    this.startLabel,
    this.compact = false,
  });
  final OffsiteVenue venue;
  final String? walkLabel;
  final String? startLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          venue.name,
          style: compact ? text.titleMedium : text.headlineSmall,
        ),
        const SizedBox(height: 4),
        if (venue.address != null)
          SelectableText(venue.address!, style: text.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            const Pill('Off-site', icon: Icons.location_city),
            if (walkLabel != null)
              Pill(
                walkLabel!,
                icon: Icons.directions_walk,
                color: Brand.neverBlue,
              ),
            if (startLabel != null)
              Pill(startLabel!, icon: Icons.door_front_door_outlined),
          ],
        ),
      ],
    );
  }
}

/// Interactive walking directions to an off-site venue on our own map.
class OutdoorDirections extends StatefulWidget {
  const OutdoorDirections({
    super.key,
    required this.map,
    required this.target,
    required this.venue,
    required this.locate,
    required this.positions,
  });

  final OutdoorMap map;
  final OutdoorTarget target;
  final OffsiteVenue venue;
  final LocationProvider locate;
  final LocationStreamProvider positions;

  @override
  State<OutdoorDirections> createState() => _OutdoorDirectionsState();
}

class _OutdoorDirectionsState extends State<OutdoorDirections> {
  final _mapKey = GlobalKey<OutdoorMapViewState>();
  final _pages = PageController();
  late OutdoorStart _start;
  OutdoorPlan? _plan;
  NavTracker? _tracker;
  int _step = 0;
  bool _arrived = false;
  UserMarker? _user;
  StreamSubscription<LocationFix>? _sub;
  bool _locating = false;
  int _locateGen = 0;
  String? _toast;
  Timer? _toastTimer;

  OutdoorMap get _map => widget.map;

  @override
  void initState() {
    super.initState();
    _start = chooseOutdoorStart(_map, widget.target.point);
    _replan(animate: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusStep(0);
      _useLocation(explicit: false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _toastTimer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _replan({bool animate = true}) {
    final plan = planWalk(_map, _start, widget.target);
    _plan = plan;
    _step = 0;
    _arrived = false;
    _tracker = plan == null ? null : NavTracker(plan.route, plan.steps);
    if (plan != null && plan.route.metres <= OutdoorNavRules.arriveMetres) {
      _arrived = true;
      _tracker!.arrived = true;
      _step = plan.steps.length - 1;
    }
    if (!animate) return;
    setState(() {});
    if (_pages.hasClients) _pages.jumpToPage(_step);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep(_step));
  }

  Rect _bounds(Iterable<Offset> pts, {double min = 140}) {
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromCenter(center: p, width: 1, height: 1));
    }
    final grow = math.max(0.0, min - math.min(r.width, r.height)) / 2;
    return r.inflate(30 + grow);
  }

  Rect _stepRect(OutdoorStep st) {
    if (st.kind == OutdoorStepKind.arrive) {
      final b = widget.target.building;
      return _bounds([
        st.end,
        widget.target.venuePos,
        if (b != null) ...b.outline,
      ]);
    }
    return _bounds(st.points);
  }

  void _focusStep(int i) {
    final plan = _plan;
    if (plan == null || i < 0 || i >= plan.steps.length) return;
    _mapKey.currentState?.animateTo(_stepRect(plan.steps[i]));
  }

  void _overview() {
    final plan = _plan;
    _mapKey.currentState?.animateTo(
      plan == null
          ? _bounds([widget.target.point.pos], min: 400)
          : _bounds([...plan.route.points, widget.target.venuePos]),
    );
  }

  void _recenter() {
    final u = _user;
    final plan = _plan;
    if (u == null || plan == null) {
      _focusStep(_step);
      return;
    }
    _mapKey.currentState?.animateTo(
      _bounds([u.pos, plan.steps[_step].end], min: 120),
    );
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _snack(String msg) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  void _onPage(int i) {
    setState(() => _step = i);
    _focusStep(i);
  }

  void _goTo(int i) => _pages.animateToPage(
    i,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
  );

  /// One-shot location to pick the start; on success also starts live
  /// tracking. [explicit] is a tap on "Use my location".
  Future<void> _useLocation({required bool explicit}) async {
    final gen = ++_locateGen;
    setState(() => _locating = true);
    LocationResult res;
    try {
      res = await widget.locate();
    } catch (_) {
      res = const LocationFailure(
        'Could not get your location. Pick a start point instead.',
      );
    }
    if (!mounted || gen != _locateGen) return;
    _locating = false;
    if (res is LocationFix) {
      _setUser(res);
      _startTracking();
      final s = chooseOutdoorStart(
        _map,
        widget.target.point,
        lat: res.lat,
        lng: res.lng,
        accuracy: res.accuracy,
      );
      if (explicit || s.kind != OutdoorStartKind.fallback) {
        _start = s;
        _replan();
      } else {
        setState(() {});
      }
      if (explicit) {
        final msg = switch (s.reason) {
          OutdoorFallbackReason.tooFar =>
            'You are more than ${OutdoorNavRules.maxDistanceMetres ~/ 1000} km away, so directions start at ${theExit(s.exit?.label ?? 'venue')}.',
          OutdoorFallbackReason.inaccurate =>
            'Your location is too imprecise right now, so directions start at ${theExit(s.exit?.label ?? 'venue')}.',
          _ =>
            s.kind == OutdoorStartKind.atVenue
                ? 'You are at the venue: leave through ${theExit(s.exit?.label ?? 'nearest exit')}.'
                : null,
        };
        if (msg != null) _snack(msg);
      }
    } else {
      setState(() {});
      if (explicit && res is LocationFailure) _snack(res.message);
    }
  }

  void _setUser(LocationFix f) {
    final pos = _map.project(f.lat, f.lng);
    // Far outside the map: nothing useful to draw.
    _user =
        _map.projection.distanceToBox(f.lat, f.lng) >
            OutdoorNavRules.maxDistanceMetres
        ? null
        : UserMarker(pos, f.accuracy, heading: f.heading);
  }

  void _startTracking() {
    if (_sub != null) return;
    try {
      _sub = widget.positions().listen(_onFix, onError: (Object _) {});
    } catch (_) {
      _sub = null;
    }
  }

  void _onFix(LocationFix f) {
    if (!mounted) return;
    _setUser(f);
    final tracker = _tracker;
    if (tracker == null || _user == null) {
      setState(() {});
      return;
    }
    final pos = _user!.pos;
    switch (tracker.update(pos, f.accuracy)) {
      case NavEvent.arrived:
        setState(() {
          _arrived = true;
          _step = tracker.step;
        });
        _goTo(tracker.step);
      case NavEvent.advanced:
        setState(() => _step = tracker.step);
        _goTo(tracker.step);
      case NavEvent.reroute:
        final canReroute =
            _start.kind != OutdoorStartKind.picked &&
            _map.distanceToVenue(pos) > OutdoorNavRules.venueMetres;
        if (!canReroute) {
          setState(() {});
          return;
        }
        final s = chooseOutdoorStart(
          _map,
          widget.target.point,
          lat: f.lat,
          lng: f.lng,
          accuracy: f.accuracy,
        );
        if (s.kind != OutdoorStartKind.gps && s.exit?.id == _start.exit?.id) {
          setState(() {});
          return;
        }
        _start = s;
        _replan();
        _showToast('Rerouted');
      case NavEvent.none:
        setState(() {});
    }
  }

  Future<void> _pickStart() async {
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
            for (final x in _map.exits)
              ListTile(
                leading: Icon(
                  x.label.toLowerCase().contains('hyatt')
                      ? Icons.hotel_outlined
                      : Icons.door_front_door_outlined,
                ),
                title: Text(x.label),
                selected: _start.fromGps == false && _start.exit?.id == x.id,
                onTap: () => Navigator.pop(ctx, x),
              ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Use my location'),
              subtitle: const Text(
                'From where you are, or the best exit if you are at the venue',
              ),
              selected: _start.fromGps,
              onTap: () => Navigator.pop(ctx, 'locate'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is VenueExit) {
      _locateGen++;
      _locating = false;
      _start = chooseOutdoorStart(_map, widget.target.point, exitId: choice.id);
      _replan();
    } else if (choice == 'locate') {
      await _useLocation(explicit: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plan = _plan;
    final media = MediaQuery.of(context);
    final toast = _arrived ? 'You have arrived' : _toast;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: OutdoorMapView(
                  key: _mapKey,
                  map: _map,
                  target: widget.target,
                  plan: plan,
                  currentStep: _step,
                  user: _user,
                  initialFocus: plan == null
                      ? null
                      : _stepRect(plan.steps[_step]),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    MapIconButton(
                      tooltip: 'Show whole route',
                      icon: Icons.fit_screen_outlined,
                      onPressed: _overview,
                    ),
                    const SizedBox(height: 8),
                    MapIconButton(
                      tooltip: 'Recenter',
                      icon: Icons.center_focus_strong_outlined,
                      onPressed: _recenter,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: _Attribution(
                  text: _map.attribution,
                  onTap: () => openLink(context, _osmCopyright),
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
                      child: toast == null
                          ? const SizedBox.shrink()
                          : _Toast(
                              key: ValueKey(toast),
                              text: toast,
                              icon: _arrived
                                  ? Icons.flag_outlined
                                  : Icons.alt_route,
                              color: _arrived
                                  ? Brand.neverBlue
                                  : Brand.swwYellow,
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
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.52),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VenueHeader(
                      venue: widget.venue,
                      compact: true,
                      walkLabel: plan == null
                          ? (widget.venue.walkMinutes == null
                                ? null
                                : '${widget.venue.walkMinutes} min walk')
                          : '${plan.route.minutes} min walk',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _start.fromGps
                                    ? Icons.my_location
                                    : Icons.door_front_door_outlined,
                                size: 18,
                              ),
                        label: Text(
                          _start.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                        tooltip: 'Change start point',
                        onPressed: _pickStart,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (plan == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No walking route found from here. Try another start point or open the route in maps.',
                          style: text.bodyMedium,
                        ),
                      )
                    else ...[
                      SizedBox(
                        height: 156,
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: plan.steps.length,
                          onPageChanged: _onPage,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: _OutdoorStepCard(
                              step: plan.steps[i],
                              index: i,
                              count: plan.steps.length,
                              arrived: _arrived,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous step',
                            onPressed: _step > 0
                                ? () => _goTo(_step - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: _Dots(
                              count: plan.steps.length,
                              index: _step,
                              onTap: _goTo,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next step',
                            onPressed: _step < plan.steps.length - 1
                                ? () => _goTo(_step + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    SubtleButton(
                      icon: Icons.open_in_new,
                      label: 'Open in maps',
                      onPressed: () =>
                          openLink(context, _mapsUrl(widget.venue)),
                    ),
                    if (widget.venue.directions.isNotEmpty)
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            'Written directions',
                            style: text.titleSmall,
                          ),
                          children: [
                            StepList(steps: _writtenSteps(widget.venue)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(_badgeNote, style: text.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
  });
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fg = color == Brand.swwYellow ? Brand.darkPage : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Brand.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: Brand.darkPage.withValues(alpha: 0.7),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 10,
            letterSpacing: -0.2,
            color: Brand.darkBody,
          ),
        ),
      ),
    ),
  );
}

class _OutdoorStepCard extends StatelessWidget {
  const _OutdoorStepCard({
    required this.step,
    required this.index,
    required this.count,
    required this.arrived,
  });
  final OutdoorStep step;
  final int index;
  final int count;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final arrive = step.kind == OutdoorStepKind.arrive;
    final cross = step.kind == OutdoorStepKind.cross;
    final badge = arrive
        ? Brand.neverBlue
        : (cross ? Brand.swwYellow : b.subtle);
    final badgeFg = arrive
        ? Colors.white
        : (cross ? Brand.darkPage : b.heading);
    final meta = [
      'Step ${index + 1} of $count',
      ?step.distanceLabel,
    ].join(' · ');
    return BrandCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
            child: Icon(outdoorStepIcon(step), color: badgeFg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  arrive && arrived ? 'You have arrived' : meta,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  step.title,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (step.hint != null) ...[
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      step.hint!,
                      style: text.bodyMedium,
                      overflow: TextOverflow.fade,
                    ),
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

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap});
  final int count;
  final int index;
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
                    ? Brand.neverBlue
                    : b.body.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(Brand.radiusPill),
              ),
            ),
          ),
      ],
    );
  }
}
