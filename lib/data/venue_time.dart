import 'package:intl/intl.dart';

/// All times are shown in conference local time (Salt Lake City, MST UTC-7
/// for the whole event: DST ended on Nov 1, 2026), regardless of where the
/// device thinks it is.
const venueUtcOffset = Duration(hours: -7);
const venueTimeZone = 'America/Denver';

/// Conference days shown as tabs.
final conferenceDays = <DateTime>[
  DateTime.utc(2026, 11, 9),
  DateTime.utc(2026, 11, 10),
  DateTime.utc(2026, 11, 11),
  DateTime.utc(2026, 11, 12),
];

/// Wall-clock time at the venue, expressed as a UTC DateTime whose fields
/// read like local time. Only use for display and day bucketing.
DateTime venueWall(DateTime instant) => instant.toUtc().add(venueUtcOffset);

/// The venue calendar day (midnight, UTC-flavoured) of an instant.
DateTime venueDay(DateTime instant) {
  final w = venueWall(instant);
  return DateTime.utc(w.year, w.month, w.day);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Index of the day tab to open: today if within the conference, else the
/// first day (or the last day once the event is over).
int defaultDayIndex(DateTime now) {
  final today = venueDay(now);
  for (var i = 0; i < conferenceDays.length; i++) {
    if (sameDay(conferenceDays[i], today)) return i;
  }
  return today.isAfter(conferenceDays.last) ? conferenceDays.length - 1 : 0;
}

final _time = DateFormat('h:mm a');
final _dayShort = DateFormat('EEE d');
final _dayLong = DateFormat('EEEE, MMM d');

String fmtTime(DateTime instant) => _time.format(venueWall(instant));
String fmtRange(DateTime start, DateTime end) =>
    '${fmtTime(start)} – ${fmtTime(end)}';
String fmtDayShort(DateTime day) => _dayShort.format(day);
String fmtDayLong(DateTime instantOrDay, {bool isDay = false}) =>
    _dayLong.format(isDay ? instantOrDay : venueWall(instantOrDay));

String fmtDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// "in 25 min", "now", "in 2 h".
String fmtRelative(DateTime instant, DateTime now) {
  final d = instant.difference(now);
  if (d.inMinutes.abs() < 1) return 'now';
  if (d.isNegative) return '${fmtDuration(-d)} ago';
  return 'in ${fmtDuration(d)}';
}
