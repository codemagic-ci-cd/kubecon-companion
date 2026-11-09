import 'dart:ui' show Offset;

import 'models.dart';

/// Where something takes place, resolved against venue.json.
sealed class ResolvedLocation {
  const ResolvedLocation();
  String get label;
}

class RoomLocation extends ResolvedLocation {
  const RoomLocation(this.room, this.level);
  final Room room;
  final Level? level;
  @override
  String get label => room.name;
  String get levelLabel => level?.name ?? room.levelId;
}

class OffsiteLocation extends ResolvedLocation {
  const OffsiteLocation(this.venue);
  final OffsiteVenue venue;
  @override
  String get label => venue.name;
}

/// A location we can't place on the map: show the raw text only.
class UnknownLocation extends ResolvedLocation {
  const UnknownLocation(this.label);
  @override
  final String label;
}

/// Turns "l2-250-a-c" into "L2 250 A C" when nothing better is known.
String humanizeId(String id) {
  if (id.isEmpty) return 'Location to be announced';
  return id
      .split(RegExp(r'[-_]+'))
      .where((p) => p.isNotEmpty)
      .map(
        (p) => p.length <= 3
            ? p.toUpperCase()
            : p[0].toUpperCase() + p.substring(1),
      )
      .join(' ');
}

ResolvedLocation resolveLocation(
  Venue venue,
  String? roomId, {
  Map<String, String> rawNames = const {},
  String? fallbackText,
}) {
  final room = venue.room(roomId);
  if (room != null) return RoomLocation(room, venue.level(room.levelId));
  final off = venue.offsiteVenue(roomId);
  if (off != null) return OffsiteLocation(off);
  final text =
      fallbackText ??
      (roomId == null ? null : rawNames[roomId]) ??
      (roomId == null || roomId.isEmpty ? null : humanizeId(roomId));
  return UnknownLocation(text ?? 'Location to be announced');
}

enum StepKind {
  start,
  walk,
  escalator,
  elevator,
  stairs,
  levelChange,
  arrive,

  /// An aside such as "Alternative: ..." or "Shortcut: ..."; not part of
  /// the main route.
  note,
}

final _noteLead = RegExp(
  r'^(alternative|alternatively|shortcut|tip|note|or)\b',
  caseSensitive: false,
);

class DirectionStep {
  const DirectionStep(this.text, this.kind, {this.toLevel});
  final String text;
  final StepKind kind;

  /// Target level number mentioned by a level-change step ("Level 2" -> "2").
  final String? toLevel;

  bool get isLevelChange =>
      kind == StepKind.escalator ||
      kind == StepKind.elevator ||
      kind == StepKind.stairs ||
      kind == StepKind.levelChange;
}

final _moveVerb = RegExp(
  r'\b(take|ride|go|head|walk|climb)\b[^.;]*\b(up|down)\b|\bup (one|two|three|a) (floor|level)|\b(up|down) to level\b|\bup to\b|\bdown to\b',
  caseSensitive: false,
);
final _levelRef = RegExp(r'\blevel\s+(\d+)', caseSensitive: false);

StepKind classifyStep(String text) {
  final t = text.toLowerCase();
  final moves = _moveVerb.hasMatch(t);
  if (!moves) return StepKind.walk;
  final positions = <StepKind, int>{
    StepKind.escalator: t.indexOf('escalator'),
    StepKind.elevator: t.indexOf('elevator'),
    StepKind.stairs: t.indexOf('stair'),
  }..removeWhere((_, v) => v < 0);
  if (positions.isEmpty) {
    return _levelRef.hasMatch(t) ? StepKind.levelChange : StepKind.walk;
  }
  return positions.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
}

/// Builds typed steps from the plain strings in venue.json.
List<DirectionStep> buildSteps(List<String> raw) {
  final steps = <DirectionStep>[];
  for (var i = 0; i < raw.length; i++) {
    final text = raw[i].trim();
    if (text.isEmpty) continue;
    if (_noteLead.hasMatch(text)) {
      steps.add(DirectionStep(text, StepKind.note));
      continue;
    }
    var kind = classifyStep(text);
    if (kind == StepKind.walk) {
      if (steps.isEmpty) kind = StepKind.start;
      final lastMain = raw
          .sublist(i + 1)
          .every((t) => t.trim().isEmpty || _noteLead.hasMatch(t.trim()));
      if (lastMain) kind = StepKind.arrive;
    }
    final lvl = kind == StepKind.walk || kind == StepKind.start
        ? null
        : _levelRef.firstMatch(text)?.group(1);
    steps.add(DirectionStep(text, kind, toLevel: lvl));
  }
  return steps;
}

/// One straight-ish segment of the suggested route, drawn on a single level.
class RouteLeg {
  const RouteLeg({
    required this.levelId,
    required this.from,
    required this.to,
    this.fromLabel,
    this.toLabel,
  });
  final String levelId;
  final Offset from;
  final Offset to;
  final String? fromLabel;
  final String? toLabel;
}

const _connectorKinds = {'escalator', 'elevator', 'stairs'};

Set<String> _tokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where(
      (t) =>
          t.length > 2 &&
          !{
            'the',
            'and',
            'level',
            'levels',
            'to',
            'up',
            'down',
            'floor',
            'floors',
            'take',
            'ride',
          }.contains(t),
    )
    .toSet();

Landmark? _bestConnector(
  Venue venue,
  String levelId,
  String hint,
  Offset near,
) {
  final candidates = venue
      .landmarksOn(levelId)
      .where((l) => _connectorKinds.contains(l.kind))
      .toList();
  if (candidates.isEmpty) return null;
  final hintTokens = _tokens(hint);
  double score(Landmark l) {
    final overlap = _tokens(l.name).intersection(hintTokens).length;
    final dist = (Offset(l.x, l.y) - near).distance;
    return overlap * 10000 - dist;
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return candidates.first;
}

/// A suggested route from the main entrance to [room], split per level.
/// The geometry is schematic: an L-shaped line between known points.
List<RouteLeg> planRoute(Venue venue, Room room) {
  final target = Offset(room.cx, room.cy);
  final ground = venue.levels.isEmpty ? 'L1' : venue.levels.first.id;
  final entrances = venue
      .landmarksOn(ground)
      .where((l) => l.kind == 'entrance')
      .toList();
  if (entrances.isEmpty) return const [];
  final entrance = entrances.firstWhere(
    (l) => l.name.toLowerCase().contains('main'),
    orElse: () => entrances.first,
  );
  final start = Offset(entrance.x, entrance.y);

  if (room.levelId == ground) {
    return [
      RouteLeg(
        levelId: ground,
        from: start,
        to: target,
        fromLabel: entrance.name,
        toLabel: room.name,
      ),
    ];
  }

  final steps = buildSteps(room.directions);
  final hint = steps.where((s) => s.isLevelChange).map((s) => s.text).join(' ');
  final isHyatt =
      (room.building ?? '').toLowerCase().contains('hyatt') ||
      room.levelId.startsWith('H');

  Landmark? groundConnector;
  if (isHyatt) {
    groundConnector = venue
        .landmarksOn(ground)
        .where((l) => l.name.toLowerCase().contains('hyatt'))
        .firstOrNull;
  }
  final upper = _bestConnector(venue, room.levelId, hint, target);
  groundConnector ??= _bestConnector(
    venue,
    ground,
    '$hint ${upper?.name ?? ''}',
    upper == null ? target : Offset(upper.x, upper.y),
  );

  final legs = <RouteLeg>[];
  if (groundConnector != null) {
    legs.add(
      RouteLeg(
        levelId: ground,
        from: start,
        to: Offset(groundConnector.x, groundConnector.y),
        fromLabel: entrance.name,
        toLabel: groundConnector.name,
      ),
    );
  }
  if (upper != null) {
    legs.add(
      RouteLeg(
        levelId: room.levelId,
        from: Offset(upper.x, upper.y),
        to: target,
        fromLabel: upper.name,
        toLabel: room.name,
      ),
    );
  }
  return legs;
}

/// Points of an L-shaped path (horizontal first, then vertical), which reads
/// more like walking corridors than a diagonal line.
List<Offset> elbowPath(Offset a, Offset b) {
  if ((a.dx - b.dx).abs() < 1 || (a.dy - b.dy).abs() < 1) return [a, b];
  return [a, Offset(b.dx, a.dy), b];
}
