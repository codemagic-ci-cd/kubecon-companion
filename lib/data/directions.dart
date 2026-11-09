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

/// "Room 251 A-C (Workshops)" -> "251 A-C".
String shortRoomLabel(String name) {
  var s = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  s = s.replaceFirst(RegExp(r'^Room\s+', caseSensitive: false), '');
  return s.isEmpty ? name : s;
}
