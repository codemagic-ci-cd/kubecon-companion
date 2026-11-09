import 'directions.dart';
import 'models.dart';
import 'venue_time.dart';

/// How long before an item starts we notify.
const reminderLead = Duration(minutes: 10);

/// iOS keeps at most 64 pending local notifications per app.
const maxScheduledReminders = 60;

/// Happening kinds that deserve a heads-up.
const notifiableHappeningKinds = {
  'meal',
  'break',
  'keynote',
  'social',
  'party',
};

class Reminder {
  const Reminder({
    required this.id,
    required this.key,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.startsAt,
    this.sessionId,
    this.personal = false,
  });

  /// Stable 31-bit id for the platform notification APIs.
  final int id;
  final String key;
  final String title;
  final String body;
  final DateTime fireAt;
  final DateTime startsAt;
  final String? sessionId;

  /// Saved or explicitly reminded by the user (vs. a general highlight).
  final bool personal;

  @override
  String toString() => 'Reminder($key @ $fireAt)';
}

/// FNV-1a, so ids stay identical across app launches and platforms.
int stableId(String key) {
  var hash = 0x811c9dc5;
  for (final c in key.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

String _dedupeKey(DateTime start, String kind, String title) {
  final minute = start.toUtc().toIso8601String().substring(0, 16);
  const grouped = {'meal', 'break', 'keynote'};
  return '$minute|${grouped.contains(kind) ? kind : _norm(title)}';
}

/// Everything that should notify, deduplicated, future-only, soonest first.
///
/// Rules: saved and reminded sessions always notify; highlighted sessions
/// notify except individual keynote talks (the keynote block from
/// happenings covers them, which keeps mornings quiet); happenings notify
/// for meals, breaks, keynote blocks and social events.
List<Reminder> buildReminders({
  required List<Session> sessions,
  required List<Happening> happenings,
  required Venue venue,
  required DateTime now,
  Set<String> saved = const {},
  Set<String> reminded = const {},
  bool includeHighlights = true,
  Map<String, String> rawRoomNames = const {},
  int max = maxScheduledReminders,
}) {
  final byKey = <String, Reminder>{};

  String where(String? roomId, String? text) {
    if ((roomId == null || roomId.isEmpty) && text == null) return '';
    final loc = resolveLocation(
      venue,
      roomId,
      rawNames: rawRoomNames,
      fallbackText: text,
    );
    return ' · ${loc.label}';
  }

  void add(Reminder r) {
    final existing = byKey[r.key];
    if (existing == null || (r.personal && !existing.personal)) {
      byKey[r.key] = r;
    }
  }

  for (final s in sessions) {
    final personal = saved.contains(s.id) || reminded.contains(s.id);
    final highlight = includeHighlights && s.highlight && s.type != 'keynote';
    if (!personal && !highlight) continue;
    final key = personal
        ? 'session|${s.id}'
        : _dedupeKey(s.start, s.type, s.title);
    add(
      Reminder(
        id: stableId(key),
        key: key,
        title: personal ? 'Starting soon: ${s.title}' : s.title,
        body: '${fmtRange(s.start, s.end)}${where(s.roomId, null)}',
        fireAt: s.start.subtract(reminderLead),
        startsAt: s.start,
        sessionId: s.id,
        personal: personal,
      ),
    );
  }

  if (includeHighlights) {
    for (final h in happenings) {
      if (!notifiableHappeningKinds.contains(h.kind)) continue;
      final key = _dedupeKey(h.start, h.kind, h.title);
      add(
        Reminder(
          id: stableId(key),
          key: key,
          title: h.title,
          body: '${fmtRange(h.start, h.end)}${where(h.roomId, h.location)}',
          fireAt: h.start.subtract(reminderLead),
          startsAt: h.start,
        ),
      );
    }
  }

  final list = byKey.values.where((r) => r.fireAt.isAfter(now)).toList()
    ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return list.length > max ? list.sublist(0, max) : list;
}
