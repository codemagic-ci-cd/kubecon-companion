import 'dart:math' as math;

/// Fixture centre; metres east/north of it are turned into lat/lng.
const fxLat = 40.765, fxLng = -111.895;

const _r = 6371000.0;

/// Lat/lng [east] and [north] metres from the fixture centre.
List<double> fxGeo(double east, double north) {
  final kLat = math.pi / 180 * _r;
  final kLng = kLat * math.cos(fxLat * math.pi / 180);
  return [fxLat + north / kLat, fxLng + east / kLng];
}

/// A small street grid (metres east, north of the centre):
///
///   n2 (0,200) --Third Ave-- n6 (100,200) --Third Ave-- n4 (200,200)
///    |                                                    |
///   Main                                               Second
///    |                                                    |
///   n0 (0,0) --First Ave-- n5 (100,0) --First Ave-- n3 (200,0)
///                                           crossing n3-n9 (220,0)
///                                           First Ave n9-n10 (300,0)
///
/// Main has a middle node n1 (0,100). The venue building sits west of Main;
/// exits at n0 ("South entrance") and n2 ("North entrance").
Map<String, dynamic> outdoorFixture() {
  final pts = <List<double>>[
    [0, 0], // 0
    [0, 100], // 1
    [0, 200], // 2
    [200, 0], // 3
    [200, 200], // 4
    [100, 0], // 5
    [100, 200], // 6
    [-500, -500], // 7 (isolated)
    [-490, -500], // 8 (isolated)
    [220, 0], // 9
    [300, 0], // 10
  ];
  final sw = fxGeo(-600, -600), ne = fxGeo(600, 600);
  return {
    'attribution': '© OpenStreetMap contributors',
    'bbox': [sw[0], sw[1], ne[0], ne[1]],
    'nodes': [for (final p in pts) fxGeo(p[0], p[1])],
    'names': ['Main', 'First Ave', 'Second', 'Third Ave', 'Lonely Lane'],
    'edges': [
      [0, 1, 0, 0],
      [1, 2, 0, 0],
      [0, 5, 1, 0],
      [5, 3, 1, 0],
      [2, 6, 3, 0],
      [6, 4, 3, 0],
      [3, 4, 2, 0],
      [7, 8, 4, 1],
      [3, 9, -1, 2],
      [9, 10, 1, 1],
    ],
    'labels': [
      {
        'name': 'Main',
        'lat': fxGeo(0, 100)[0],
        'lng': fxGeo(0, 100)[1],
        'angle': 90,
      },
    ],
    'buildings': [
      {
        'name': 'Convention Center',
        'kind': 'venue',
        'outline': [
          fxGeo(-80, 0),
          fxGeo(-10, 0),
          fxGeo(-10, 200),
          fxGeo(-80, 200),
        ],
      },
      {
        'name': 'Example Hotel',
        'kind': 'destination',
        'outline': [
          fxGeo(80, 210),
          fxGeo(120, 210),
          fxGeo(120, 240),
          fxGeo(80, 240),
        ],
      },
    ],
    'venueExits': [
      {
        'id': 'south',
        'label': 'South entrance',
        'lat': fxGeo(-10, 0)[0],
        'lng': fxGeo(-10, 0)[1],
        'node': 0,
      },
      {
        'id': 'north',
        'label': 'North entrance',
        'lat': fxGeo(-10, 200)[0],
        'lng': fxGeo(-10, 200)[1],
        'node': 2,
      },
    ],
    'destinations': {
      'offsite-hotel': {
        'node': 6,
        'lat': fxGeo(100, 220)[0],
        'lng': fxGeo(100, 220)[1],
      },
    },
  };
}
