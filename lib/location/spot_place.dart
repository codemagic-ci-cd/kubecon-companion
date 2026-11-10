import 'dart:ui' show Offset;

import '../data/official_map.dart';
import '../data/spot_link.dart';
import '../state/app_state.dart' show ConferenceData;
import 'geo_projection.dart';
import 'start_point.dart';

/// A shared spot placed on the venue map.
class SpotPlacement {
  const SpotPlacement({
    required this.spot,
    this.pos,
    this.regionId,
    this.place,
    this.targetRoomId,
    this.offVenue = false,
    this.metresAway = 0,
  });

  final SharedSpot spot;

  /// Image px of the pin; null when it cannot be drawn (unknown room, or a
  /// GPS spot away from the venue).
  final Offset? pos;

  /// Map panel the pin is on.
  final String? regionId;

  /// "Hall A-C", "North Foyer escalators": what the card says it is near.
  final String? place;

  /// Venue room the indoor route goes to; null when there is none.
  final String? targetRoomId;

  /// A GPS spot more than [GeoProjection.offMapMetres] outside the building.
  final bool offVenue;

  /// Metres from the building outline for a GPS spot (0 inside).
  final double metresAway;

  /// "about 450 m" / "about 2.3 km".
  String get awayLabel {
    if (metresAway >= 1000) {
      return '${(metresAway / 1000).toStringAsFixed(1)} km';
    }
    final m = ((metresAway / 10).round() * 10).clamp(10, 990);
    return '$m m';
  }
}

/// Places [spot] on the venue map of [data].
SpotPlacement placeSpot(ConferenceData data, SharedSpot spot) {
  final map = data.officialMap;
  final roomId = spot.roomId;
  if (roomId != null) {
    final room = data.venue.room(roomId);
    final geo = map?.room(roomId, partOf: room?.partOf);
    return SpotPlacement(
      spot: spot,
      pos: geo?.rect.center,
      regionId: geo?.regionId,
      place: room?.name,
      targetRoomId: room?.id,
    );
  }
  final lat = spot.lat!, lng = spot.lng!;
  final proj = map == null ? null : GeoProjection.of(map);
  if (map == null || proj == null) {
    return SpotPlacement(spot: spot, offVenue: true, metresAway: 0);
  }
  final away = distanceToFootprint(map, lat, lng);
  if (away > GeoProjection.offMapMetres) {
    return SpotPlacement(spot: spot, offVenue: true, metresAway: away);
  }
  final ground = groundAnchors(map).toSet();
  final near = nearestGeoNode(map, lat, lng, where: ground.contains)?.$1;
  final pos = proj.toImage(lat, lng);
  return SpotPlacement(
    spot: spot,
    pos: pos,
    regionId: GeoProjection.regionId,
    place: near?.place ?? near?.label,
    targetRoomId: nearestRoutableRoom(data, pos, GeoProjection.regionId),
    metresAway: away,
  );
}

/// The venue room at [pos] on panel [regionId] when it has a door on the
/// walking graph, else the one whose door is nearest. Null when none.
String? nearestRoutableRoom(ConferenceData data, Offset pos, String regionId) {
  final map = data.officialMap;
  if (map == null) return null;
  bool routable(String id) {
    final room = data.venue.room(id);
    return room != null && map.doorFor(room.id, partOf: room.partOf) != null;
  }

  final hit = map.roomAt(pos);
  if (hit != null && routable(hit)) return hit;
  String? best;
  var bestD = double.infinity;
  for (final room in data.venue.rooms) {
    final door = map.doorFor(room.id, partOf: room.partOf);
    if (door == null || door.regionId != regionId) continue;
    final d = (door.pos - pos).distance;
    if (d < bestD) {
      bestD = d;
      best = room.id;
    }
  }
  return best;
}
