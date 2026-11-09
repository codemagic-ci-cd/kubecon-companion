import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/official_map.dart';

/// Small, hand-written data set mirroring the shape of assets/data.
final venueJson = <String, dynamic>{
  'name': 'Test Convention Center',
  'address': '1 Main St',
  'isApproximate': true,
  'levels': [
    {'id': 'L2', 'name': 'Level 2', 'order': 2},
    {'id': 'L1', 'name': 'Level 1', 'order': 1},
  ],
  'landmarks': [
    {
      'id': 'e',
      'name': '200 South (Main) Entrance',
      'levelId': 'L1',
      'kind': 'entrance',
      'x': 10,
      'y': 500,
    },
    {
      'id': 'esc1',
      'name': 'North Foyer escalators (to Level 2)',
      'levelId': 'L1',
      'kind': 'escalator',
      'x': 600,
      'y': 480,
    },
    {
      'id': 'esc155',
      'name': '155 wing escalators',
      'levelId': 'L1',
      'kind': 'escalator',
      'x': 800,
      'y': 420,
    },
    {
      'id': 'esc2',
      'name': 'North Foyer escalators (to Level 1)',
      'levelId': 'L2',
      'kind': 'escalator',
      'x': 600,
      'y': 480,
    },
    {
      'id': 'food',
      'name': 'Lunch',
      'levelId': 'L1',
      'kind': 'food',
      'x': 300,
      'y': 100,
    },
  ],
  'rooms': [
    {
      'id': 'l1-hall-de',
      'name': 'Hall DE (Keynotes)',
      'aliases': ['Salt Palace | Level 1 | Hall DE'],
      'levelId': 'L1',
      'x': 100,
      'y': 100,
      'w': 200,
      'h': 200,
      'directions': [
        'Enter through the 200 South (Main) Entrance',
        'Walk north along the Lower Concourse',
        'Hall DE is the first hall on your left',
      ],
    },
    {
      'id': 'l2-250',
      'name': 'Room 250 A-C',
      'levelId': 'L2',
      'x': 650,
      'y': 300,
      'w': 100,
      'h': 80,
      'directions': [
        'Enter through the 200 South (Main) Entrance',
        'Walk north along the Lower Concourse',
        'At the north end, take the North Foyer escalators (elevator alongside) up one floor to Level 2',
        'Walk north along the Upper Concourse',
        'Room 250 A-C is the first room on your right',
      ],
    },
  ],
  'offsite': [
    {
      'id': 'offsite-hotel',
      'name': 'Example Hotel',
      'address': '225 West 200 South',
      'lat': 40.76,
      'lng': -111.89,
      'walkMinutes': 4,
      'directions': [
        'Exit onto 200 South',
        'Turn right',
        'The hotel is on your left',
      ],
    },
  ],
};

/// A session entry in the shape of assets/data/schedule.json.
Map<String, dynamic> session(
  String id,
  String start,
  String end, {
  String type = 'talk',
  String room = 'l1-hall-de',
  bool highlight = false,
  String? title,
  List<String> prerequisites = const [],
}) => {
  'id': id,
  'title': title ?? 'Session $id',
  'start': start,
  'end': end,
  'type': type,
  'track': 'Observability',
  'roomId': room,
  'level': 'beginner',
  'speakers': ['ada'],
  'url': 'https://example.com/$id',
  'highlight': highlight,
  'hasPrerequisites': prerequisites.isNotEmpty,
};

/// Prerequisites per session id; they live in details.json.
const _prerequisites = {
  't1': ['Laptop with kind installed'],
};

final scheduleJson = <String, dynamic>{
  'source': 'sample',
  'fetchedAt': '2026-11-09T09:00:00-07:00',
  'isSample': true,
  'speakers': {
    'ada': {
      'name': 'Ada Example',
      'title': 'Engineer',
      'company': 'Example Co',
      'links': {'github': 'ada-gh'},
    },
  },
  'sessions': [
    session(
      'k1',
      '2026-11-10T09:00:00-07:00',
      '2026-11-10T09:15:00-07:00',
      type: 'keynote',
      highlight: true,
    ),
    session(
      't1',
      '2026-11-10T11:30:00-07:00',
      '2026-11-10T12:00:00-07:00',
      room: 'l2-250',
      title: 'Scaling CI on Kubernetes',
      prerequisites: _prerequisites['t1']!,
    ),
    session(
      't2',
      '2026-11-10T11:30:00-07:00',
      '2026-11-10T12:00:00-07:00',
      room: 'unknown-room',
    ),
    session(
      'lunch',
      '2026-11-10T12:50:00-07:00',
      '2026-11-10T14:50:00-07:00',
      type: 'meal',
      highlight: true,
      title: 'Lunch',
    ),
    session(
      'party',
      '2026-11-10T18:00:00-07:00',
      '2026-11-10T19:30:00-07:00',
      type: 'social',
      highlight: true,
      room: 'offsite-hotel',
      title: 'Reception',
    ),
    session(
      'w1',
      '2026-11-11T10:00:00-07:00',
      '2026-11-11T11:00:00-07:00',
      type: 'workshop',
    ),
  ],
};

/// details.json for [scheduleJson]: descriptions, prerequisites, bios.
final detailsJson = <String, dynamic>{
  'sessions': {
    for (final s in scheduleJson['sessions'] as List)
      (s as Map)['id']: {
        'description': 'About ${s['id']}',
        'prerequisites': ?_prerequisites[s['id']],
      },
  },
  'speakers': {
    'ada': {
      'bio': 'Builds things.',
      'photo': 'https://cdn.example.com/ada.jpg',
      'links': {'linkedin': 'https://www.linkedin.com/in/ada/'},
    },
  },
};

final happeningsJson = <String, dynamic>{
  'items': [
    {
      'id': 'lunch-10',
      'title': 'Lunch',
      'start': '2026-11-10T12:50:00-07:00',
      'end': '2026-11-10T14:50:00-07:00',
      'kind': 'meal',
      'location': 'Solutions Showcase',
      'roomId': null,
      'description': 'Lunch is served.',
    },
    {
      'id': 'keynotes-10',
      'title': 'Keynotes',
      'start': '2026-11-10T09:00:00-07:00',
      'end': '2026-11-10T10:45:00-07:00',
      'kind': 'keynote',
      'roomId': 'l1-hall-de',
    },
    {
      'id': 'quiet-10',
      'title': 'Quiet room',
      'start': '2026-11-10T07:00:00-07:00',
      'end': '2026-11-10T20:00:00-07:00',
      'kind': 'other',
      'roomId': 'l2-260a',
      'location': 'Level 2 | 260A',
    },
    {'title': 'Broken item without start'},
  ],
};

Venue testVenue() => Venue.fromJson(venueJson);
ScheduleData testSchedule() => ScheduleData.fromJson(scheduleJson);
ConferenceDetails testDetails() => ConferenceDetails.fromJson(detailsJson);
List<Happening> testHappenings() => Happening.listFromJson(happeningsJson);

/// A tiny annotated map in the shape of assets/data/official_map.json.
final officialMapJson = <String, dynamic>{
  'image': 'assets/maps/kcna26_venue_map.jpg',
  'width': 1000,
  'height': 1000,
  'regions': [
    {
      'id': 'sp-L1',
      'label': 'Salt Palace Level 1',
      'building': 'Salt Palace',
      'levelId': 'L1',
      'rect': [0, 0, 600, 500],
    },
    {
      'id': 'sp-L2',
      'label': 'Salt Palace Level 2',
      'building': 'Salt Palace',
      'levelId': 'L2',
      'rect': [0, 500, 600, 500],
    },
    {
      'id': 'hy-L2',
      'label': 'Hyatt Regency Level 2',
      'building': 'Hyatt Regency',
      'levelId': 'H2',
      'rect': [600, 0, 400, 400],
    },
  ],
  'rooms': {
    'l1-hall-de': {'x': 100, 'y': 150, 'w': 150, 'h': 150, 'regionId': 'sp-L1'},
    'l2-250': {'x': 120, 'y': 600, 'w': 100, 'h': 80, 'regionId': 'sp-L2'},
  },
  'nodes': [
    {
      'id': 'sp-entrance-200-south',
      'x': 20,
      'y': 100,
      'regionId': 'sp-L1',
      'kind': 'entrance',
      'label': '200 South entrance',
      'lat': 40.765,
      'lng': -111.8957,
    },
    {
      'id': 'sp-entrance-west-temple',
      'x': 500,
      'y': 100,
      'regionId': 'sp-L1',
      'kind': 'entrance',
      'label': 'West Temple entrance',
      'lat': 40.7661,
      'lng': -111.8935,
    },
    {'id': 'j1', 'x': 100, 'y': 100, 'regionId': 'sp-L1', 'kind': 'junction'},
    {
      'id': 'door-l1-hall-de',
      'x': 175,
      'y': 140,
      'regionId': 'sp-L1',
      'kind': 'door',
    },
    {
      'id': 'esc1',
      'x': 300,
      'y': 100,
      'regionId': 'sp-L1',
      'kind': 'escalator',
    },
    {
      'id': 'lift1',
      'x': 350,
      'y': 100,
      'regionId': 'sp-L1',
      'kind': 'elevator',
    },
    {
      'id': 'esc2',
      'x': 300,
      'y': 560,
      'regionId': 'sp-L2',
      'kind': 'escalator',
    },
    {
      'id': 'lift2',
      'x': 350,
      'y': 560,
      'regionId': 'sp-L2',
      'kind': 'elevator',
    },
    {
      'id': 'door-l2-250',
      'x': 170,
      'y': 590,
      'regionId': 'sp-L2',
      'kind': 'door',
    },
  ],
  'edges': [
    {
      'from': 'sp-entrance-200-south',
      'to': 'j1',
      'kind': 'walk',
      'hint': 'Pass Badge Pick-Up on your left',
    },
    {'from': 'j1', 'to': 'door-l1-hall-de', 'kind': 'walk'},
    {'from': 'j1', 'to': 'esc1', 'kind': 'walk'},
    {'from': 'esc1', 'to': 'lift1', 'kind': 'walk'},
    {'from': 'lift1', 'to': 'sp-entrance-west-temple', 'kind': 'walk'},
    {
      'from': 'esc1',
      'to': 'esc2',
      'kind': 'escalator',
      'hint': 'North Foyer escalators',
    },
    {'from': 'lift1', 'to': 'lift2', 'kind': 'elevator'},
    {'from': 'esc2', 'to': 'lift2', 'kind': 'walk'},
    {'from': 'esc2', 'to': 'door-l2-250', 'kind': 'walk'},
  ],
};

OfficialMap testOfficialMap() => OfficialMap.fromJson(officialMapJson);
