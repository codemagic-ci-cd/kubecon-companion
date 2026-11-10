import 'dart:convert';

import 'agenda_link.dart' show kAppBaseUrl;

/// Query parameter that carries a shared spot ("Share my spot").
const kSpotParam = 'at';

/// Version prefix of the current spot payload format.
const kSpotPrefix = 'v1.';

/// Longest name and note kept from a link.
const kSpotNameMax = 40;
const kSpotNoteMax = 120;
const _roomIdMax = 80;

/// Spots shared longer ago than this get a "may have moved on" warning.
const kSpotStaleAfter = Duration(hours: 2);

/// Where someone said they are: a venue room (or a sponsor's hall), or a GPS
/// position. No backend: everything is in the link.
class SharedSpot {
  SharedSpot({
    required String name,
    this.roomId,
    double? lat,
    double? lng,
    String? note,
    required DateTime time,
  }) : name = _clip(name, kSpotNameMax),
       note = _blankToNull(_clip(note ?? '', kSpotNoteMax)),
       lat = lat == null ? null : _round5(lat),
       lng = lng == null ? null : _round5(lng),
       time = DateTime.fromMillisecondsSinceEpoch(
         time.millisecondsSinceEpoch ~/ 1000 * 1000,
         isUtc: true,
       );

  final String name;

  /// Venue room id; null for a GPS spot.
  final String? roomId;

  /// GPS position rounded to 5 decimals (about 1 m); null for a room spot.
  final double? lat;
  final double? lng;
  final String? note;

  /// When it was shared (UTC, whole seconds).
  final DateTime time;

  bool get isRoom => roomId != null;
  bool get hasGeo => lat != null && lng != null;

  /// How long ago it was shared; never negative (clock skew).
  Duration age(DateTime now) {
    final d = now.difference(time);
    return d.isNegative ? Duration.zero : d;
  }

  bool isStale(DateTime now) => age(now) > kSpotStaleAfter;

  @override
  bool operator ==(Object other) =>
      other is SharedSpot &&
      other.name == name &&
      other.roomId == roomId &&
      other.lat == lat &&
      other.lng == lng &&
      other.note == note &&
      other.time == time;

  @override
  int get hashCode => Object.hash(name, roomId, lat, lng, note, time);

  @override
  String toString() =>
      'SharedSpot($name, ${roomId ?? '$lat,$lng'}, $note, $time)';
}

String _clip(String s, int max) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  final runes = t.runes.toList();
  return runes.length <= max
      ? t
      : String.fromCharCodes(runes.take(max)).trimRight();
}

String? _blankToNull(String s) => s.isEmpty ? null : s;

double _round5(double v) => (v * 100000).round() / 100000;

/// `https://kubecon.codemagic.app/?at=v1.…` for [spot].
String spotLink(SharedSpot spot) =>
    '$kAppBaseUrl?$kSpotParam=${encodeSpot(spot)}';

/// Encodes [spot] as `v1.` + base64url (no padding) of the JSON array
/// `[name, place, note, unixSeconds]`, where place is the room id string or
/// `[lat·1e5, lng·1e5]` as integers, and note is omitted when empty.
String encodeSpot(SharedSpot spot) {
  final Object place = spot.roomId ?? [_e5(spot.lat!), _e5(spot.lng!)];
  final secs = spot.time.millisecondsSinceEpoch ~/ 1000;
  final json = jsonEncode([spot.name, place, spot.note ?? '', secs]);
  final b64 = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  return '$kSpotPrefix$b64';
}

int _e5(double v) => (v * 100000).round();

/// The spot in [payload], or null when it is not a valid spot payload.
/// Never throws.
SharedSpot? decodeSpot(String payload) {
  final p = payload.trim();
  if (!p.startsWith(kSpotPrefix) || p.length > 1200) return null;
  try {
    final raw = utf8.decode(
      base64Url.decode(base64Url.normalize(p.substring(kSpotPrefix.length))),
    );
    final j = jsonDecode(raw);
    if (j is! List || j.length < 4) return null;
    final name = j[0], place = j[1], note = j[2], secs = j[3];
    if (name is! String || name.trim().isEmpty) return null;
    if (note is! String || secs is! int || secs <= 0) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
    if (place is String) {
      final id = place.trim();
      if (id.isEmpty || id.length > _roomIdMax) return null;
      return SharedSpot(name: name, roomId: id, note: note, time: time);
    }
    if (place is List && place.length == 2) {
      final la = place[0], ln = place[1];
      if (la is! int || ln is! int) return null;
      final lat = la / 100000, lng = ln / 100000;
      if (lat.abs() > 90 || lng.abs() > 180) return null;
      return SharedSpot(name: name, lat: lat, lng: lng, note: note, time: time);
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// The raw spot payload of a link, or null when it carries none. Never
/// throws.
String? spotParamFrom(Uri uri) {
  try {
    final v = uri.queryParameters[kSpotParam];
    return v == null || v.isEmpty ? null : v;
  } catch (_) {
    return null;
  }
}

/// "just now", "12 min ago", "3 h 5 min ago".
String fmtSpotAge(Duration age) {
  final m = age.inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h >= 48) return '${h ~/ 24} days ago';
  final r = m % 60;
  return r == 0 ? '$h h ago' : '$h h $r min ago';
}
