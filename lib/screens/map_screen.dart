import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/session_tile.dart';
import '../widgets/venue_map.dart';
import 'directions_screen.dart';

/// Indoor venue map. As a tab it browses freely; pushed with [focusRoomId]
/// it highlights that room and draws the suggested route per level.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.focusRoomId});
  final String? focusRoomId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapKey = GlobalKey<VenueMapViewState>();
  String? _levelId;
  String? _selectedRoomId;

  @override
  void initState() {
    super.initState();
    final venue = AppScope.read(context).data.venue;
    final focus = venue.room(widget.focusRoomId);
    _selectedRoomId = focus?.id;
    _levelId =
        focus?.levelId ?? (venue.levels.isEmpty ? null : venue.levels.first.id);
  }

  void _selectRoom(Room room) {
    setState(() {
      _selectedRoomId = room.id;
      _levelId = room.levelId;
    });
    _showRoomSheet(room);
  }

  void _showRoomSheet(Room room) {
    final app = AppScope.read(context);
    final now = app.now;
    final upcoming = app.data.sessions
        .where((s) => s.roomId == room.id && s.end.isAfter(now))
        .take(4)
        .toList();
    final level = app.data.venue.level(room.levelId);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AppScope(
        state: app,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: upcoming.isEmpty ? 0.35 : 0.6,
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
                    Text(
                      room.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        room.building,
                        level?.name,
                      ].whereType<String>().toSet().join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (room.note != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        room.note!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        icon: Icons.directions,
                        label: 'Step-by-step directions',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          Navigator.of(this.context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DirectionsScreen(roomId: room.id),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (upcoming.isNotEmpty) ...[
                const SectionTitle('Coming up here'),
                for (final s in upcoming)
                  SessionTile(session: s, showDay: true),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _searchRooms() async {
    final app = AppScope.read(context);
    final room = await showSearch<Room?>(
      context: context,
      delegate: _RoomSearch(app.data.venue),
    );
    if (room != null && mounted) {
      setState(() {
        _selectedRoomId = room.id;
        _levelId = room.levelId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final venue = app.data.venue;
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final focusRoom = venue.room(widget.focusRoomId);
    final route = focusRoom == null
        ? const <RouteLeg>[]
        : planRoute(venue, focusRoom);
    final levelId = _levelId;
    final level = levelId == null ? null : venue.level(levelId);
    final routeLevels = route.map((l) => l.levelId).toList();

    if (venue.levels.isEmpty || levelId == null) {
      return Scaffold(
        appBar: AppBar(title: const AppBarTitle()),
        body: const EmptyState(
          icon: Icons.map_outlined,
          title: 'Map unavailable',
          message: 'The venue map could not be loaded.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: focusRoom == null
            ? const AppBarTitle()
            : Text('Route to ${shortRoomLabel(focusRoom.name)}'),
        actions: [
          IconButton(
            tooltip: 'Find a room',
            icon: const Icon(Icons.search),
            onPressed: _searchRooms,
          ),
          if (focusRoom == null) const SettingsAction(),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final l in venue.levels)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(l.shortName),
                      selected: l.id == levelId,
                      showCheckmark: false,
                      avatar: routeLevels.contains(l.id)
                          ? Icon(
                              Icons.route,
                              size: 16,
                              color: l.id == levelId
                                  ? Colors.white
                                  : Brand.swwYellow,
                            )
                          : null,
                      labelStyle: text.labelLarge?.copyWith(
                        color: l.id == levelId ? Colors.white : b.heading,
                      ),
                      onSelected: (_) => setState(() => _levelId = l.id),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    level?.description ?? level?.name ?? '',
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: VenueMapView(
                    key: _mapKey,
                    venue: venue,
                    levelId: levelId,
                    highlightRoomId: _selectedRoomId,
                    route: route,
                    onRoomTap: _selectRoom,
                    onLandmarkTap: (l) => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(l.name))),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 8,
                  child: Column(
                    children: [
                      _MapButton(
                        tooltip: 'Reset zoom',
                        icon: Icons.fit_screen_outlined,
                        onPressed: () => _mapKey.currentState?.resetView(),
                      ),
                      const SizedBox(height: 8),
                      const _Compass(),
                    ],
                  ),
                ),
                if (focusRoom != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _RouteBar(
                      room: focusRoom,
                      route: route,
                      levelId: levelId,
                      venue: venue,
                      onLevel: (id) => setState(() => _levelId = id),
                    ),
                  ),
              ],
            ),
          ),
          if (venue.isApproximate && focusRoom == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Schematic map, not to scale. Tap a room for details; follow onsite signage.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
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

/// North indicator; the map is drawn north-up in portrait, north-right in
/// landscape.
class _Compass extends StatelessWidget {
  const _Compass();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final northUp = size.height > size.width * 0.95;
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.brand.subtle,
          borderRadius: BorderRadius.circular(Brand.radiusMd),
        ),
        child: RotatedBox(
          quarterTurns: northUp ? 0 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.navigation, size: 16, color: Brand.swwYellow),
              Text(
                'N',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontSize: 10, height: 1),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _RouteBar extends StatelessWidget {
  const _RouteBar({
    required this.room,
    required this.route,
    required this.levelId,
    required this.venue,
    required this.onLevel,
  });

  final Room room;
  final List<RouteLeg> route;
  final String levelId;
  final Venue venue;
  final ValueChanged<String> onLevel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final idx = route.indexWhere((l) => l.levelId == levelId);
    final leg = idx < 0 ? null : route[idx];
    final next = idx >= 0 && idx < route.length - 1 ? route[idx + 1] : null;
    final prev = idx > 0 ? route[idx - 1] : null;
    String levelName(String id) => venue.level(id)?.shortName ?? id;

    return BrandCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.route, color: Brand.swwYellow),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  leg == null
                      ? 'Route is on ${route.map((l) => levelName(l.levelId)).join(' → ')}'
                      : 'From ${leg.fromLabel ?? 'start'}',
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  next != null
                      ? 'Then go to ${levelName(next.levelId)}'
                      : (leg != null ? 'To ${room.name}' : room.name),
                  style: text.labelLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (prev != null)
            IconButton(
              tooltip: 'Previous level',
              onPressed: () => onLevel(prev.levelId),
              icon: const Icon(Icons.arrow_back),
            ),
          if (next != null)
            FilledButton(
              onPressed: () => onLevel(next.levelId),
              child: Text(levelName(next.levelId)),
            )
          else if (leg == null && route.isNotEmpty)
            FilledButton(
              onPressed: () => onLevel(route.first.levelId),
              child: const Text('Start'),
            ),
        ],
      ),
    );
  }
}

class _RoomSearch extends SearchDelegate<Room?> {
  _RoomSearch(this.venue) : super(searchFieldLabel: 'Find a room');
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
    final list = venue.rooms.where((r) {
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.aliases.any((a) => a.toLowerCase().contains(q));
    }).toList();
    return list;
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
