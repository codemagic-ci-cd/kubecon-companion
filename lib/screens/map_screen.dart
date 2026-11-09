import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/official_map.dart';
import '../location/live_location.dart';
import '../location/start_point.dart';
import '../services/location_service.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/official_map_view.dart';
import '../widgets/session_tile.dart';
import 'directions_screen.dart';

/// The official venue map with our room boxes: pan, zoom, jump to a panel,
/// tap a room for what's on there and directions.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.active = true,
    this.locate = currentLocation,
    this.positions = locationStream,
  });

  /// The Map tab is showing; live location pauses while it is not.
  final bool active;

  /// Permission + first fix and live positions (injectable for tests).
  final LocationProvider locate;
  final LocationStreamProvider positions;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _mapKey = GlobalKey<OfficialMapViewState>();
  String? _selectedRoomId;
  String? _regionId = 'sp-L1';
  LiveLocationController? _live;
  bool _foreground = true;

  /// False while another route covers the Map tab (tickers are muted then).
  bool _onScreen = true;

  AppState? _app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Handles [AppState.showOnMap]: selects the room once this tab is up.
  void _onMapFocus() {
    final req = _app?.mapFocus.value;
    if (req == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = _app;
      if (!mounted || app == null || app.mapFocus.value != req) return;
      app.mapFocus.value = null;
      final room = app.data.venue.room(req.roomId);
      if (room != null) _selectRoom(room, moveCamera: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.read(context);
    if (!identical(app, _app)) {
      _app?.mapFocus.removeListener(_onMapFocus);
      _app = app..mapFocus.addListener(_onMapFocus);
      _onMapFocus();
    }
    final on = TickerMode.valuesOf(context).enabled;
    if (on != _onScreen) {
      _onScreen = on;
      _syncLive();
    }
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncLive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncLive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app?.mapFocus.removeListener(_onMapFocus);
    _live?.dispose();
    super.dispose();
  }

  /// Runs the position stream only while the tab is visible, not covered by
  /// another route, and the app is in the foreground.
  void _syncLive() {
    final live = _live;
    if (live == null) return;
    if (widget.active && _onScreen && _foreground) {
      live.resume();
    } else {
      live.pause();
    }
  }

  LiveLocationController _liveFor(OfficialMap map) => _live ??=
      LiveLocationController(
          map: map,
          locate: widget.locate,
          positions: widget.positions,
        )
        ..onFollowFix = _followDot
        ..addListener(_onLive);

  LiveStatus? _lastStatus;

  void _onLive() {
    final live = _live!;
    if (live.status != _lastStatus &&
        live.status == LiveStatus.unavailable &&
        live.error != null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(live.error!)));
    }
    _lastStatus = live.status;
    if (mounted) setState(() {});
  }

  /// Keeps the camera on the dot while following.
  void _followDot() {
    final p = _live?.placement.value;
    if (p == null || p.offMap || !mounted) return;
    if (_regionId != 'sp-L1') setState(() => _regionId = 'sp-L1');
    _mapKey.currentState?.centerOn(p.pos);
  }

  Future<void> _locateMe(OfficialMap map) => _liveFor(map).locateMe();

  void _goToRegion(MapRegion r) {
    _live?.userMoved();
    setState(() => _regionId = r.id);
    _mapKey.currentState?.animateTo(r.rect, padding: 8);
  }

  void _fitAll() {
    _live?.userMoved();
    setState(() => _regionId = null);
    _mapKey.currentState?.fit();
  }

  void _selectRoom(Room room, {bool moveCamera = false}) {
    final map = AppScope.read(context).data.officialMap;
    final geo = map?.room(room.id, partOf: room.partOf);
    _live?.userMoved();
    setState(() {
      _selectedRoomId = room.id;
      if (geo != null) _regionId = geo.regionId;
    });
    if (geo != null) {
      // Keep the room in view above the room sheet (about half the map).
      _mapKey.currentState?.animateTo(
        geo.rect.inflate(moveCamera ? 220 : 160),
        bottomFraction: 0.5,
      );
    }
    _showRoomSheet(room);
  }

  void _showRoomSheet(Room room) {
    final app = AppScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => AppScope(
        state: app,
        child: RoomSheet(
          room: room,
          onDirections: () {
            Navigator.pop(sheetContext);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DirectionsScreen(roomId: room.id),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _searchRooms() async {
    final app = AppScope.read(context);
    final room = await showSearch<Room?>(
      context: context,
      delegate: RoomSearchDelegate(app.data.venue),
    );
    if (room != null && mounted) _selectRoom(room, moveCamera: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final map = app.data.officialMap;
    final venue = app.data.venue;

    if (map == null) {
      return Scaffold(
        appBar: AppBar(title: const AppBarTitle()),
        body: const EmptyState(
          icon: Icons.map_outlined,
          title: 'Map unavailable',
          message: 'The venue map could not be loaded.',
        ),
      );
    }
    final selected = venue.room(_selectedRoomId);
    final selectedGeo = selected == null
        ? null
        : map.room(selected.id, partOf: selected.partOf);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(),
        actions: [
          IconButton(
            tooltip: 'Find a room',
            icon: const Icon(Icons.search),
            onPressed: _searchRooms,
          ),
          const SettingsAction(),
        ],
      ),
      body: Column(
        children: [
          RegionChips(map: map, selectedId: _regionId, onSelected: _goToRegion),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.white,
                    child: OfficialMapView(
                      key: _mapKey,
                      map: map,
                      // Open on the main Salt Palace floor: the whole poster is tiny on a phone.
                      initialFocus: map.region('sp-L1')?.rect,
                      selectedRoomId: selectedGeo?.id,
                      liveLocation: _live?.placement,
                      onUserMove: () => _live?.userMoved(),
                      onRoomTap: (id) {
                        final room = venue.room(id);
                        if (room != null) _selectRoom(room);
                      },
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      MapIconButton(
                        tooltip: 'Show whole map',
                        icon: Icons.fit_screen_outlined,
                        onPressed: _fitAll,
                      ),
                      const SizedBox(height: 8),
                      LocateMeButton(
                        status: _live?.status ?? LiveStatus.off,
                        follow: _live?.follow ?? false,
                        onPressed: () => _locateMe(map),
                      ),
                    ],
                  ),
                ),
                if (_live?.placement.value case final p?)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: LiveLocationChip(
                        placement: p,
                        onDirections: () {
                          final entrance = map.node(OfficialMap.mainEntranceId);
                          if (entrance != null) {
                            openLink(context, walkingDirectionsUrl(entrance));
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          mapCredit(context, map, (url) => openLink(context, url)),
        ],
      ),
    );
  }
}

/// "Salt Palace: L1 L2 L3 · Hyatt: L2 L3 L4 L5" panel chips.
class RegionChips extends StatelessWidget {
  const RegionChips({
    super.key,
    required this.map,
    required this.selectedId,
    required this.onSelected,
    this.highlight = const {},
    this.inline = false,
  });

  final OfficialMap map;
  final String? selectedId;
  final ValueChanged<MapRegion> onSelected;

  /// Regions the current route passes through.
  final Set<String> highlight;

  /// Just the chips, for embedding in another horizontal scroller.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    Widget group(String title, List<MapRegion> regions) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: text.labelLarge),
        const SizedBox(width: 8),
        for (final r in regions)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('L${map.floorOf(r.id)}'),
              tooltip: r.label,
              selected: r.id == selectedId,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              avatar: highlight.contains(r.id)
                  ? Icon(
                      Icons.route,
                      size: 16,
                      color: r.id == selectedId
                          ? Colors.white
                          : Brand.swwYellow,
                    )
                  : null,
              labelStyle: text.labelLarge?.copyWith(
                color: r.id == selectedId ? Colors.white : b.heading,
              ),
              onSelected: (_) => onSelected(r),
            ),
          ),
      ],
    );
    final sp = map.regions.where((r) => !r.isHyatt).toList();
    final hy = map.regions.where((r) => r.isHyatt).toList();
    final chips = [
      if (sp.isNotEmpty) group('Salt Palace', sp),
      if (sp.isNotEmpty && hy.isNotEmpty) const SizedBox(width: 12),
      if (hy.isNotEmpty) group('Hyatt', hy),
    ];
    if (inline) return Row(mainAxisSize: MainAxisSize.min, children: chips);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: chips,
      ),
    );
  }
}

/// The "Locate me" map button: subtle when off, blue while following,
/// dimmed when location is unavailable (tap to retry).
class LocateMeButton extends StatelessWidget {
  const LocateMeButton({
    super.key,
    required this.status,
    required this.follow,
    required this.onPressed,
  });

  final LiveStatus status;
  final bool follow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final on = status == LiveStatus.live && follow;
    final unavailable = status == LiveStatus.unavailable;
    return IconButton.filled(
      tooltip: switch (status) {
        LiveStatus.unavailable => 'Location unavailable, tap to retry',
        LiveStatus.live when !follow => 'Centre on me',
        _ => 'Locate me',
      },
      style: IconButton.styleFrom(
        backgroundColor: on ? Brand.neverBlue : b.subtle,
        foregroundColor: on
            ? Colors.white
            : unavailable
            ? b.heading.withValues(alpha: 0.4)
            : (status == LiveStatus.live ? Brand.neverBlue : b.heading),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusMd),
        ),
      ),
      onPressed: onPressed,
      icon: status == LiveStatus.starting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(unavailable ? Icons.location_disabled : Icons.my_location),
    );
  }
}

/// "You · near Badge Pick-Up · ±12 m · floor unknown", or how far away the
/// venue is when the fix is off the map.
class LiveLocationChip extends StatelessWidget {
  const LiveLocationChip({
    super.key,
    required this.placement,
    required this.onDirections,
  });

  final LivePlacement placement;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final p = placement;
    final label = p.offMap
        ? "You're about ${p.awayLabel} from the venue"
        : [
            'You',
            if (p.near?.place != null) 'near ${p.near!.place}',
            '±${p.accuracyMetres} m',
            'floor unknown',
          ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: b.isDark ? Brand.darkSubtle : Colors.white,
        borderRadius: BorderRadius.circular(Brand.radiusMd),
        border: Border.all(color: b.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.my_location, size: 16, color: Brand.neverBlue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: text.labelLarge?.copyWith(color: b.heading),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (p.offMap) ...[
            const SizedBox(height: 8),
            SubtleButton(
              icon: Icons.directions_walk,
              label: 'Directions to the venue',
              onPressed: onDirections,
            ),
          ],
        ],
      ),
    );
  }
}

class MapIconButton extends StatelessWidget {
  const MapIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    style: IconButton.styleFrom(
      backgroundColor: context.brand.subtle,
      foregroundColor: context.brand.heading,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
      ),
    ),
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// Sessions running now and next in a room (including its sub-rooms).
({List<Session> now, List<Session> next}) roomSchedule(
  AppState app,
  Room room,
) {
  final venue = app.data.venue;
  bool inRoom(Session s) {
    if (s.roomId == room.id) return true;
    final r = venue.room(s.roomId);
    return r != null && (r.id == room.id || r.partOf == room.id);
  }

  final t = app.now;
  final here = app.data.sessions.where(inRoom).toList();
  final now = here.where((s) => !t.isBefore(s.start) && t.isBefore(s.end));
  final later = here.where((s) => s.start.isAfter(t)).toList();
  final next = later.isEmpty
      ? <Session>[]
      : later.where((s) => s.start == later.first.start).toList();
  return (now: now.toList(), next: next);
}

class RoomSheet extends StatelessWidget {
  const RoomSheet({super.key, required this.room, required this.onDirections});
  final Room room;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final level = app.data.venue.level(room.levelId);
    final sched = roomSchedule(app, room);
    final hasSessions = sched.now.isNotEmpty || sched.next.isNotEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: hasSessions ? 0.55 : 0.3,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name, style: text.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  [
                    room.building ?? 'Salt Palace',
                    // "Hyatt Regency - Level 4" -> "Level 4" after the
                    // building name, so it is not repeated.
                    level?.name.replaceFirst(
                      RegExp(r'^.*\s[-–]\s(?=Level)'),
                      '',
                    ),
                  ].whereType<String>().toSet().join(' · '),
                  style: text.bodyMedium,
                ),
                if (room.note != null) ...[
                  const SizedBox(height: 8),
                  Text(room.note!, style: text.bodySmall),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    icon: Icons.directions,
                    label: 'Directions',
                    onPressed: onDirections,
                  ),
                ),
              ],
            ),
          ),
          if (sched.now.isNotEmpty) ...[
            const SectionTitle('Now'),
            for (final s in sched.now) SessionTile(session: s),
          ],
          if (sched.next.isNotEmpty) ...[
            const SectionTitle('Next'),
            for (final s in sched.next) SessionTile(session: s, showDay: true),
          ],
          if (!hasSessions)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Nothing else scheduled here.',
                style: text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class RoomSearchDelegate extends SearchDelegate<Room?> {
  RoomSearchDelegate(this.venue, {String label = 'Find a room'})
    : super(searchFieldLabel: label);
  final Venue venue;

  @override
  ThemeData appBarTheme(BuildContext context) {
    final t = Theme.of(context);
    return t.copyWith(
      inputDecorationTheme: t.inputDecorationTheme.copyWith(
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear',
        icon: const Icon(Icons.close),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  List<Room> _results() {
    final q = query.trim().toLowerCase();
    return venue.rooms.where((r) {
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.aliases.any((a) => a.toLowerCase().contains(q));
    }).toList();
  }

  Widget _list(BuildContext context) {
    final rooms = _results();
    if (rooms.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No rooms found',
        message: 'Try a room number like 250 or a name like Hall DE.',
      );
    }
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, i) {
        final r = rooms[i];
        return ListTile(
          leading: const Icon(Icons.meeting_room_outlined),
          title: Text(r.name),
          subtitle: Text(venue.level(r.levelId)?.name ?? r.levelId),
          onTap: () => close(context, r),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);
}
