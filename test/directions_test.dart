import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/directions.dart';
import 'package:kubecon_companion/data/models.dart';

import 'fixtures.dart';

void main() {
  group('step classification', () {
    test('level changes are detected with the right conveyance', () {
      expect(
        classifyStep(
          'Take the North Foyer escalators (elevator alongside) up one floor to Level 2',
        ),
        StepKind.escalator,
      );
      expect(
        classifyStep('Take the Hyatt Regency elevators up to Level 4'),
        StepKind.elevator,
      );
      expect(
        classifyStep(
          'Take the escalators or elevator in the 155 wing lobby up two floors to Level 3',
        ),
        StepKind.escalator,
      );
      expect(classifyStep('Walk up the stairs to Level 2'), StepKind.stairs);
    });

    test('mentioning an escalator without using it is a walking step', () {
      expect(
        classifyStep('Pass the escalators on your left and keep walking north'),
        StepKind.walk,
      );
    });

    test('buildSteps marks start, arrival and target level', () {
      final room = testVenue().room('l2-250')!;
      final steps = buildSteps(room.directions);
      expect(steps.first.kind, StepKind.start);
      expect(steps.last.kind, StepKind.arrive);
      final change = steps.singleWhere((s) => s.isLevelChange);
      expect(change.kind, StepKind.escalator);
      expect(change.toLevel, '2');
    });

    test('alternatives are notes, not level changes or the arrival', () {
      final steps = buildSteps([
        'Enter the building',
        'Take the escalators up to Level 2',
        'Room 255 D is on your left',
        'Alternative: from Level 1 take the elevator up one floor',
      ]);
      expect(steps.where((s) => s.isLevelChange), hasLength(1));
      expect(steps[2].kind, StepKind.arrive);
      expect(steps.last.kind, StepKind.note);
    });

    test('empty strings are dropped', () {
      expect(buildSteps(['', '  ', 'Go']).single.text, 'Go');
    });
  });

  group('location resolution', () {
    final venue = testVenue();

    test('rooms, off-site venues and unknown ids', () {
      expect(resolveLocation(venue, 'l2-250'), isA<RoomLocation>());
      expect(resolveLocation(venue, 'offsite-hotel'), isA<OffsiteLocation>());
      final raw = resolveLocation(
        venue,
        'mystery',
        rawNames: {'mystery': 'Salt Palace | Level 9 | Attic'},
      );
      expect(raw, isA<UnknownLocation>());
      expect(raw.label, 'Salt Palace | Level 9 | Attic');
      expect(resolveLocation(venue, 'l2-260a').label, 'L2 260a');
      expect(
        resolveLocation(venue, null, fallbackText: 'Any Info Desk').label,
        'Any Info Desk',
      );
      expect(resolveLocation(venue, '').label, 'Location to be announced');
    });
  });

  group('route planning', () {
    final venue = testVenue();

    test('same-level room: one leg from the main entrance', () {
      final legs = planRoute(venue, venue.room('l1-hall-de')!);
      expect(legs, hasLength(1));
      expect(legs.single.levelId, 'L1');
      expect(legs.single.from, const Offset(10, 500));
      expect(legs.single.to, const Offset(200, 200));
    });

    test('upper-level room: via the matching escalator on both levels', () {
      final legs = planRoute(venue, venue.room('l2-250')!);
      expect(legs.map((l) => l.levelId), ['L1', 'L2']);
      expect(
        legs.first.to,
        const Offset(600, 480),
      ); // North Foyer, not 155 wing
      expect(legs.last.from, const Offset(600, 480));
      expect(legs.last.to, const Offset(700, 340));
    });

    test('elbow path is L-shaped', () {
      expect(elbowPath(Offset.zero, const Offset(10, 10)), [
        Offset.zero,
        const Offset(10, 0),
        const Offset(10, 10),
      ]);
    });

    test('every room in the bundled venue gets a route', () {
      final venue = Venue.fromJson(
        jsonDecode(File('assets/data/venue.json').readAsStringSync()),
      );
      for (final r in venue.rooms) {
        final legs = planRoute(venue, r);
        expect(legs, isNotEmpty, reason: r.id);
        expect(legs.last.levelId, r.levelId, reason: r.id);
      }
    });
  });
}
