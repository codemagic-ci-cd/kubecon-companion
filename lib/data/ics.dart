import 'dart:convert';

import 'directions.dart';
import 'models.dart';

/// Main venue line used in calendar LOCATION fields.
const kVenueCalendarAddress =
    'Salt Palace Convention Center, 100 S West Temple, Salt Lake City';

/// Hotel line for rooms in the Hyatt Regency (levels H2-H5).
const kHyattCalendarAddress =
    'Hyatt Regency Salt Lake City, 170 S West Temple, Salt Lake City';

/// UID domain for exported events.
const kIcsUidDomain = 'kubecon.codemagic.app';

/// One VEVENT.
class IcsEvent {
  const IcsEvent({
    required this.uid,
    required this.start,
    required this.end,
    required this.summary,
    this.location,
    this.description,
    this.url,
  });

  final String uid;
  final DateTime start;
  final DateTime end;
  final String summary;
  final String? location;
  final String? description;
  final String? url;
}

/// Calendar LOCATION text for a resolved room.
String icsLocation(ResolvedLocation loc) => switch (loc) {
  RoomLocation l => _roomLocation(l),
  OffsiteLocation o =>
    o.venue.address == null || o.venue.address!.isEmpty
        ? o.label
        : '${o.label}, ${o.venue.address}',
  UnknownLocation u =>
    u.label.isEmpty
        ? kVenueCalendarAddress
        : '${u.label} · $kVenueCalendarAddress',
};

String _roomLocation(RoomLocation l) {
  final building = l.level?.building ?? '';
  final hyatt = building.toLowerCase().contains('hyatt');
  // "Hyatt Regency - Level 4" -> "Level 4": the address names the building.
  var level = l.levelLabel;
  if (building.isNotEmpty && level.startsWith('$building - ')) {
    level = level.substring(building.length + 3);
  }
  return '${l.label} · $level · '
      '${hyatt ? kHyattCalendarAddress : kVenueCalendarAddress}';
}

/// A VEVENT for [s] at [loc].
IcsEvent icsEventFor(Session s, ResolvedLocation loc) {
  final speakers = s.speakers.map((p) => p.name).where((n) => n.isNotEmpty);
  final description = [
    if (speakers.isNotEmpty)
      '${speakers.length == 1 ? 'Speaker' : 'Speakers'}: ${speakers.join(', ')}',
    ?s.url,
  ].join('\n');
  return IcsEvent(
    uid: '${s.id}@$kIcsUidDomain',
    start: s.start,
    end: s.end,
    summary: s.title,
    location: icsLocation(loc),
    description: description.isEmpty ? null : description,
    url: s.url,
  );
}

/// RFC 5545 calendar with [events]; CRLF line endings, folded at 75 octets.
String buildIcs(List<IcsEvent> events, {required DateTime stamp}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Codemagic//KubeCon Companion//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
  ];
  for (final e in events) {
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${icsEscape(e.uid)}',
      'DTSTAMP:${icsDateTime(stamp)}',
      'DTSTART:${icsDateTime(e.start)}',
      'DTEND:${icsDateTime(e.end)}',
      'SUMMARY:${icsEscape(e.summary)}',
      if (e.location != null) 'LOCATION:${icsEscape(e.location!)}',
      if (e.description != null) 'DESCRIPTION:${icsEscape(e.description!)}',
      if (e.url != null) 'URL:${e.url}',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${icsEscape(e.summary)}',
      'TRIGGER:-PT10M',
      'END:VALARM',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(icsFold).join('\r\n')}\r\n';
}

/// `20261110T173000Z`.
String icsDateTime(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// Escapes a TEXT value (RFC 5545 3.3.11).
String icsEscape(String v) => v
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\n', '\\n');

/// Folds [line] so no physical line exceeds 75 octets, never splitting a
/// UTF-8 character (RFC 5545 3.1).
String icsFold(String line) {
  final out = StringBuffer();
  var used = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final size = utf8.encode(ch).length;
    if (used + size > 75) {
      out.write('\r\n ');
      used = 1;
    }
    out.write(ch);
    used += size;
  }
  return out.toString();
}

/// `scaling-ci-on-kubernetes`, at most 40 characters.
String icsSlug(String title) {
  final s = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final cut = s.length > 40 ? s.substring(0, 40) : s;
  final trimmed = cut.replaceAll(RegExp(r'-+$'), '');
  return trimmed.isEmpty ? 'session' : trimmed;
}
