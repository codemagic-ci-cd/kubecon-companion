// Tolerant data models for the JSON files in assets/data.
//
// Every parser accepts nulls, missing keys and unexpected types, because the
// data is scraped from public sources and may change shape between refreshes.

String _str(Object? v, [String fallback = '']) =>
    v == null ? fallback : (v is String ? v : v.toString());

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.trim().isEmpty ? null : s;
}

double _num(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(Object? v) => v == true || v == 'true' || v == 1;

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : const [];

List<String> _strings(Object? v) => v is List
    ? v.where((e) => e != null).map((e) => e.toString()).toList()
    : const [];

/// Parses an ISO-8601 timestamp to a UTC instant. Returns null when invalid.
DateTime? parseInstant(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toUtc();
}

class Speaker {
  const Speaker({
    required this.name,
    this.id,
    this.title,
    this.company,
    this.bio,
    this.photo,
    this.links = const SpeakerLinks(),
  });

  /// Key into the speaker maps of schedule.json / details.json; null for
  /// speakers given inline (no profile).
  final String? id;
  final String name;
  final String? title;
  final String? company;
  final String? bio;

  /// Photo URL (may be null or fail to load; show initials then).
  final String? photo;
  final SpeakerLinks links;

  factory Speaker.fromJson(Map<String, dynamic> j, {String? id}) => Speaker(
    id: id ?? _strOrNull(j['id']),
    name: _str(j['name'], 'Speaker'),
    title: _strOrNull(j['title']),
    company: _strOrNull(j['company']),
    bio: _strOrNull(j['bio']),
    photo: _strOrNull(j['photo']),
    links: SpeakerLinks.fromJson(j['links']),
  );

  String get role => [title, company].whereType<String>().join(' · ');

  /// This speaker with bio, photo and extra links from details.json.
  Speaker withDetails(SpeakerDetails? d) => d == null
      ? this
      : Speaker(
          id: id,
          name: name,
          title: title,
          company: company,
          bio: d.bio ?? bio,
          photo: d.photo ?? photo,
          links: links.mergedWith(d.links),
        );
}

/// The part of a speaker that is loaded after startup (details.json).
class SpeakerDetails {
  const SpeakerDetails({
    this.bio,
    this.photo,
    this.links = const SpeakerLinks(),
  });

  final String? bio;
  final String? photo;
  final SpeakerLinks links;

  factory SpeakerDetails.fromJson(Map<String, dynamic> j) => SpeakerDetails(
    bio: _strOrNull(j['bio']),
    photo: _strOrNull(j['photo']),
    links: SpeakerLinks.fromJson(j['links']),
  );
}

/// Raw social links as they come from the data: x/github are usually bare
/// handles, the rest full URLs. See widgets/speaker_card.dart for display.
class SpeakerLinks {
  const SpeakerLinks({
    this.x,
    this.github,
    this.linkedin,
    this.bluesky,
    this.website,
  });

  final String? x;
  final String? github;
  final String? linkedin;
  final String? bluesky;
  final String? website;

  factory SpeakerLinks.fromJson(Object? v) {
    if (v is! Map) return const SpeakerLinks();
    return SpeakerLinks(
      x: _strOrNull(v['x']),
      github: _strOrNull(v['github']),
      linkedin: _strOrNull(v['linkedin']),
      bluesky: _strOrNull(v['bluesky']),
      website: _strOrNull(v['website']),
    );
  }

  /// Fills links missing here from [other].
  SpeakerLinks mergedWith(SpeakerLinks other) => SpeakerLinks(
    x: x ?? other.x,
    github: github ?? other.github,
    linkedin: linkedin ?? other.linkedin,
    bluesky: bluesky ?? other.bluesky,
    website: website ?? other.website,
  );
}

/// Session types from the data contract, with a readable label.
const sessionTypeLabels = <String, String>{
  'keynote': 'Keynote',
  'talk': 'Talk',
  'workshop': 'Workshop',
  'lightning': 'Lightning talk',
  'panel': 'Panel',
  'tutorial': 'Tutorial',
  'colocated': 'Co-located event',
  'break': 'Break',
  'meal': 'Meal',
  'social': 'Social',
  'expo': 'Expo',
  'registration': 'Registration',
  'party': 'Party',
  'other': 'Other',
};

String typeLabel(String type) =>
    sessionTypeLabels[type] ??
    (type.isEmpty ? 'Other' : type[0].toUpperCase() + type.substring(1));

class Session {
  const Session({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.type,
    required this.roomId,
    this.track,
    this.description = '',
    this.level,
    this.prerequisites = const [],
    this.speakers = const [],
    this.url,
    this.highlight = false,
    this._hasPrerequisites = false,
  });

  final String id;
  final String title;
  final DateTime start; // UTC
  final DateTime end; // UTC
  final String type;
  final String? track;
  final String roomId;
  final String description;
  final String? level;
  final List<String> prerequisites;
  final List<Speaker> speakers;
  final String? url;
  final bool highlight;

  /// Known from schedule.json before [prerequisites] (details.json) loads.
  bool get hasPrerequisites => _hasPrerequisites || prerequisites.isNotEmpty;
  final bool _hasPrerequisites;

  /// Parses a session. [speakers] resolves speaker ids (schedule.json); the
  /// older inline format with speaker objects, description and prerequisites
  /// is accepted too.
  static Session? fromJson(
    Map<String, dynamic> j, [
    Map<String, Speaker> speakers = const {},
  ]) {
    final start = parseInstant(j['start']);
    if (start == null) return null;
    final end =
        parseInstant(j['end']) ?? start.add(const Duration(minutes: 30));
    final prerequisites = _strings(j['prerequisites']);
    return Session(
      id: _str(j['id'], '${j['title']}-${j['start']}'),
      title: _str(j['title'], 'Untitled session').trim(),
      start: start,
      end: end.isBefore(start) ? start : end,
      type: _str(j['type'], 'other').toLowerCase(),
      track: _strOrNull(j['track']),
      roomId: _str(j['roomId']),
      description: _str(j['description']).trim(),
      level: _strOrNull(j['level']),
      prerequisites: prerequisites,
      speakers: [
        if (j['speakers'] case final List list)
          for (final p in list)
            if (p is Map)
              Speaker.fromJson(p.cast<String, dynamic>())
            else if (p is String || p is num)
              ?speakers[p.toString()],
      ],
      url: _strOrNull(j['url']),
      highlight: _bool(j['highlight']),
      hasPrerequisites: _bool(j['hasPrerequisites']),
    );
  }

  /// This session with description, prerequisites and speaker bios from
  /// details.json. Inline values are kept when details have none.
  Session withDetails(ConferenceDetails? d) {
    if (d == null) return this;
    final sd = d.sessions[id];
    return Session(
      id: id,
      title: title,
      start: start,
      end: end,
      type: type,
      roomId: roomId,
      track: track,
      description: (sd?.description.isNotEmpty ?? false)
          ? sd!.description
          : description,
      level: level,
      prerequisites: (sd?.prerequisites.isNotEmpty ?? false)
          ? sd!.prerequisites
          : prerequisites,
      speakers: [
        for (final p in speakers)
          p.withDetails(p.id == null ? null : d.speakers[p.id]),
      ],
      url: url,
      highlight: highlight,
      hasPrerequisites: hasPrerequisites,
    );
  }

  String get typeName => typeLabel(type);

  String? get levelName => switch (level) {
    null || 'any' => null,
    final l => l[0].toUpperCase() + l.substring(1),
  };
}

class ScheduleData {
  const ScheduleData({
    required this.sessions,
    this.source,
    this.fetchedAt,
    this.isSample = false,
  });

  final List<Session> sessions;
  final String? source;
  final DateTime? fetchedAt;
  final bool isSample;

  factory ScheduleData.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : <String, dynamic>{};
    final raw = json is List ? json : j['sessions'];
    final speakers = <String, Speaker>{
      if (j['speakers'] case final Map m)
        for (final e in m.entries)
          if (e.value is Map)
            e.key.toString(): Speaker.fromJson(
              (e.value as Map).cast<String, dynamic>(),
              id: e.key.toString(),
            ),
    };
    final sessions =
        (raw is List ? raw : const [])
            .whereType<Map>()
            .map((m) => Session.fromJson(m.cast<String, dynamic>(), speakers))
            .whereType<Session>()
            .toList()
          ..sort((a, b) {
            final c = a.start.compareTo(b.start);
            return c != 0 ? c : a.title.compareTo(b.title);
          });
    return ScheduleData(
      sessions: sessions,
      source: _strOrNull(j['source']),
      fetchedAt: parseInstant(j['fetchedAt']),
      isSample: _bool(j['isSample']),
    );
  }
}

/// Long text loaded after the first frame (details.json): descriptions,
/// prerequisites and speaker bios/photos/links.
class SessionDetails {
  const SessionDetails({this.description = '', this.prerequisites = const []});

  final String description;
  final List<String> prerequisites;

  factory SessionDetails.fromJson(Map<String, dynamic> j) => SessionDetails(
    description: _str(j['description']).trim(),
    prerequisites: _strings(j['prerequisites']),
  );
}

class ConferenceDetails {
  const ConferenceDetails({this.sessions = const {}, this.speakers = const {}});

  final Map<String, SessionDetails> sessions;
  final Map<String, SpeakerDetails> speakers;

  factory ConferenceDetails.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : <String, dynamic>{};
    Map<String, T> parse<T>(Object? v, T Function(Map<String, dynamic>) f) => {
      if (v case final Map m)
        for (final e in m.entries)
          if (e.value is Map)
            e.key.toString(): f((e.value as Map).cast<String, dynamic>()),
    };
    return ConferenceDetails(
      sessions: parse(j['sessions'], SessionDetails.fromJson),
      speakers: parse(j['speakers'], SpeakerDetails.fromJson),
    );
  }
}

class Level {
  const Level({
    required this.id,
    required this.name,
    required this.order,
    this.building,
    this.description,
  });

  final String id;
  final String name;
  final int order;
  final String? building;
  final String? description;

  factory Level.fromJson(Map<String, dynamic> j) => Level(
    id: _str(j['id']),
    name: _str(j['name'], _str(j['id'])),
    order: _num(j['order']).toInt(),
    building: _strOrNull(j['building']),
    description: _strOrNull(j['description']),
  );

  /// Short label for the level switcher, e.g. "L1" or "Hyatt 4".
  String get shortName {
    if (id.startsWith('H') && id.length <= 3) return 'Hyatt ${id.substring(1)}';
    return name.replaceFirst('Level ', 'L');
  }
}

class Landmark {
  const Landmark({
    required this.id,
    required this.name,
    required this.levelId,
    required this.kind,
    required this.x,
    required this.y,
  });

  final String id;
  final String name;
  final String levelId;
  final String kind;
  final double x;
  final double y;

  factory Landmark.fromJson(Map<String, dynamic> j) => Landmark(
    id: _str(j['id']),
    name: _str(j['name']),
    levelId: _str(j['levelId']),
    kind: _str(j['kind'], 'info'),
    x: _num(j['x']),
    y: _num(j['y']),
  );
}

class Room {
  const Room({
    required this.id,
    required this.name,
    required this.levelId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.aliases = const [],
    this.directions = const [],
    this.building,
    this.partOf,
    this.note,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String levelId;
  final double x, y, w, h;
  final List<String> directions;
  final String? building;
  final String? partOf;
  final String? note;

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id: _str(j['id']),
    name: _str(j['name'], _str(j['id'])),
    aliases: _strings(j['aliases']),
    levelId: _str(j['levelId']),
    x: _num(j['x']),
    y: _num(j['y']),
    w: _num(j['w'], 40),
    h: _num(j['h'], 30),
    directions: _strings(j['directions']),
    building: _strOrNull(j['building']),
    partOf: _strOrNull(j['partOf']),
    note: _strOrNull(j['note']),
  );

  double get cx => x + w / 2;
  double get cy => y + h / 2;
  bool contains(double px, double py) =>
      px >= x && px <= x + w && py >= y && py <= y + h;
}

class OffsiteVenue {
  const OffsiteVenue({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.walkMinutes,
    this.directions = const [],
  });

  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final int? walkMinutes;
  final List<String> directions;

  factory OffsiteVenue.fromJson(Map<String, dynamic> j) => OffsiteVenue(
    id: _str(j['id']),
    name: _str(j['name'], _str(j['id'])),
    address: _strOrNull(j['address']),
    lat: j['lat'] == null ? null : _num(j['lat']),
    lng: j['lng'] == null ? null : _num(j['lng']),
    walkMinutes: j['walkMinutes'] == null
        ? null
        : _num(j['walkMinutes']).round(),
    directions: _strings(j['directions']),
  );
}

class Venue {
  Venue({
    required this.name,
    required this.address,
    required this.isApproximate,
    required this.levels,
    required this.landmarks,
    required this.rooms,
    required this.offsite,
    this.notes,
  }) {
    for (final r in rooms) {
      _roomIndex[r.id.toLowerCase()] = r;
      for (final a in r.aliases) {
        _roomIndex.putIfAbsent(a.toLowerCase(), () => r);
      }
      _roomIndex.putIfAbsent(r.name.toLowerCase(), () => r);
    }
    for (final o in offsite) {
      _offsiteIndex[o.id.toLowerCase()] = o;
    }
  }

  final String name;
  final String address;
  final bool isApproximate;
  final List<Level> levels;
  final List<Landmark> landmarks;
  final List<Room> rooms;
  final List<OffsiteVenue> offsite;
  final String? notes;

  final _roomIndex = <String, Room>{};
  final _offsiteIndex = <String, OffsiteVenue>{};

  static Venue empty() => Venue(
    name: 'Venue',
    address: '',
    isApproximate: true,
    levels: const [],
    landmarks: const [],
    rooms: const [],
    offsite: const [],
  );

  factory Venue.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : <String, dynamic>{};
    final levels = _maps(j['levels']).map(Level.fromJson).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Venue(
      name: _str(j['name'], 'Venue'),
      address: _str(j['address']),
      isApproximate: j['isApproximate'] == null || _bool(j['isApproximate']),
      levels: levels,
      landmarks: _maps(j['landmarks']).map(Landmark.fromJson).toList(),
      rooms: _maps(j['rooms']).map(Room.fromJson).toList(),
      offsite: _maps(j['offsite']).map(OffsiteVenue.fromJson).toList(),
      notes: _strOrNull(j['notes']),
    );
  }

  Room? room(String? id) => id == null ? null : _roomIndex[id.toLowerCase()];
  OffsiteVenue? offsiteVenue(String? id) =>
      id == null ? null : _offsiteIndex[id.toLowerCase()];

  Level? level(String id) {
    for (final l in levels) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<Room> roomsOn(String levelId) =>
      rooms.where((r) => r.levelId == levelId).toList();
  List<Landmark> landmarksOn(String levelId) =>
      landmarks.where((l) => l.levelId == levelId).toList();
}

/// Kinds of happenings (non-session things worth knowing about).
const happeningKinds = {
  'meal',
  'break',
  'keynote',
  'social',
  'party',
  'expo',
  'registration',
  'other',
};

class Happening {
  const Happening({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.kind,
    this.location,
    this.roomId,
    this.description = '',
    this.url,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String kind;
  final String? location;
  final String? roomId;
  final String description;
  final String? url;

  static Happening? fromJson(Map<String, dynamic> j) {
    final start = parseInstant(j['start']);
    if (start == null) return null;
    final end = parseInstant(j['end']) ?? start.add(const Duration(hours: 1));
    return Happening(
      id: _str(j['id'], '${j['title']}-${j['start']}'),
      title: _str(j['title'], 'Happening'),
      start: start,
      end: end.isBefore(start) ? start : end,
      kind: _str(j['kind'], 'other').toLowerCase(),
      location: _strOrNull(j['location']),
      roomId: _strOrNull(j['roomId']),
      description: _str(j['description']).trim(),
      url: _strOrNull(j['url']),
    );
  }

  static List<Happening> listFromJson(Object? json) {
    final raw = json is List
        ? json
        : (json is Map ? (json['items'] ?? json['happenings']) : null);
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((m) => Happening.fromJson(m.cast<String, dynamic>()))
        .whereType<Happening>()
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Facilities (quiet room, first aid, ...) run all day; they are listed
  /// separately and never trigger notifications.
  bool get isFacility => kind == 'other' || kind == 'registration';
}

class InfoLink {
  const InfoLink(this.title, this.url);
  final String title;
  final String url;
}

class ConferenceInfo {
  const ConferenceInfo({
    this.wifi,
    this.codeOfConduct,
    this.venueAddress,
    this.emergency,
    this.links = const [],
  });

  final String? wifi;
  final String? codeOfConduct;
  final String? venueAddress;
  final String? emergency;
  final List<InfoLink> links;

  factory ConferenceInfo.fromJson(Object? json) {
    final j = json is Map ? json.cast<String, dynamic>() : <String, dynamic>{};
    final wifi = j['wifi'];
    return ConferenceInfo(
      wifi: wifi is Map
          ? [
              wifi['network'] ?? wifi['ssid'],
              wifi['password'],
            ].whereType<Object>().join(' / ')
          : _strOrNull(wifi),
      codeOfConduct: _strOrNull(j['codeOfConduct']),
      venueAddress: _strOrNull(j['venueAddress']),
      emergency: _strOrNull(j['emergency']),
      links: _maps(j['links'])
          .where((l) => _strOrNull(l['url']) != null)
          .map(
            (l) => InfoLink(_str(l['title'], _str(l['url'])), _str(l['url'])),
          )
          .toList(),
    );
  }
}

/// Raw room names from the schedule source, used when a roomId is missing
/// from venue.json.
Map<String, String> parseRawRoomNames(Object? json) {
  final rooms = json is Map ? json['rooms'] : json;
  final out = <String, String>{};
  for (final r in _maps(rooms)) {
    final id = _strOrNull(r['id']);
    final name = _strOrNull(r['name']) ?? _strOrNull(r['raw']);
    if (id != null && name != null) out[id] = name;
  }
  return out;
}
