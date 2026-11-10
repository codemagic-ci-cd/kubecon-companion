import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/venue_time.dart';
import '../screens/session_detail_screen.dart';
import '../screens/tagged_sessions_screen.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../services/analytics.dart';

/// Whether [s] takes place in [room] or one of its sub-rooms
/// (e.g. "Grand Ballroom B" inside "Grand Ballroom BDF").
bool sessionInRoom(AppState app, Room room, Session s) {
  if (s.roomId == room.id) return true;
  final r = app.data.venue.room(s.roomId);
  return r != null && (r.id == room.id || r.partOf == room.id);
}

/// Every session in [room], across all days.
List<Session> sessionsInRoom(AppState app, Room room) =>
    app.data.sessions.where((s) => sessionInRoom(app, room, s)).toList();

/// Opens the full schedule of [room], upcoming first.
void openRoomSchedule(BuildContext context, Room room) {
  track(Events.roomSchedule, {'room': room.name});
  final app = AppScope.read(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TaggedSessionsScreen(
        title: room.name,
        filter: (s) => sessionInRoom(app, room, s),
      ),
    ),
  );
}

/// One-line "Next here" strip for the directions screen: what's on now or
/// next at the destination, plus a link to the room's full schedule.
class RoomNextStrip extends StatelessWidget {
  const RoomNextStrip({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final all = sessionsInRoom(app, room)
      ..sort((a, b) => a.start.compareTo(b.start));
    if (all.isEmpty) return const SizedBox.shrink();
    final t = app.now;
    final current = all
        .where((s) => !t.isBefore(s.start) && t.isBefore(s.end))
        .toList();
    final upcoming = all.where((s) => s.start.isAfter(t)).toList();
    final Session? show = current.isNotEmpty
        ? current.first
        : (upcoming.isNotEmpty ? upcoming.first : null);
    final today = venueDay(t);
    String when(Session s) {
      if (current.contains(s)) return 'Now';
      final d = venueDay(s.start);
      final day = sameDay(d, today) ? 'Today' : fmtDayShort(d);
      return '$day ${fmtTime(s.start)}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.event_note, size: 18, color: context.brand.icon),
          const SizedBox(width: 8),
          Expanded(
            child: show == null
                ? Text(
                    'Nothing else scheduled here',
                    style: text.bodySmall,
                    maxLines: 1,
                  )
                : InkWell(
                    borderRadius: BorderRadius.circular(Brand.radiusMd),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SessionDetailScreen(sessionId: show.id),
                      ),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${when(show)} · ',
                            style: text.labelMedium?.copyWith(
                              color: current.contains(show)
                                  ? Brand.nativeOrange
                                  : context.brand.heading,
                            ),
                          ),
                          TextSpan(text: show.title, style: text.bodySmall),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          TextButton(
            onPressed: () => openRoomSchedule(context, room),
            child: Text('All ${all.length} here'),
          ),
        ],
      ),
    );
  }
}
