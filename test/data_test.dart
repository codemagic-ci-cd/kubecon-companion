import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/directions.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/venue_time.dart';

import 'fixtures.dart';

void main() {
  group('parsing', () {
    test('sessions parse, sort and convert times to UTC', () {
      final s = testSchedule();
      expect(s.isSample, isTrue);
      expect(s.sessions, hasLength(6));
      expect(s.sessions.first.id, 'k1');
      expect(s.sessions.first.start, DateTime.utc(2026, 11, 10, 16));
      expect(fmtTime(s.sessions.first.start), '9:00 AM');
      final t1 = s.sessions.firstWhere((x) => x.id == 't1');
      expect(t1.prerequisites, ['Laptop with kind installed']);
      expect(t1.speakers.single.role, 'Engineer · Example Co');
      expect(t1.levelName, 'Beginner');
    });

    test('tolerates nulls, missing fields and junk', () {
      final s = ScheduleData.fromJson({
        'sessions': [
          {'id': 'a', 'start': '2026-11-10T09:00:00-07:00'},
          {'id': 'b', 'start': 'not a date'},
          'junk',
          {
            'id': 'c',
            'start': '2026-11-10T10:00:00-07:00',
            'end': null,
            'speakers': null,
            'prerequisites': [null, 'x'],
            'highlight': null,
            'level': 'any',
          },
        ],
      });
      expect(s.sessions.map((e) => e.id), ['a', 'c']);
      final c = s.sessions.last;
      expect(c.end.difference(c.start), const Duration(minutes: 30));
      expect(c.speakers, isEmpty);
      expect(c.prerequisites, ['x']);
      expect(c.highlight, isFalse);
      expect(c.levelName, isNull);
      expect(ScheduleData.fromJson(null).sessions, isEmpty);
      expect(Venue.fromJson('nonsense').rooms, isEmpty);
    });

    test('happenings skip invalid entries and flag facilities', () {
      final h = testHappenings();
      expect(h, hasLength(3));
      expect(h.first.title, 'Quiet room');
      expect(h.first.isFacility, isTrue);
      expect(h.where((e) => e.kind == 'meal').single.isFacility, isFalse);
    });

    test('venue lookup by id, alias and name; levels sorted', () {
      final v = testVenue();
      expect(v.levels.map((l) => l.id), ['L1', 'L2']);
      expect(v.room('L1-HALL-DE')?.name, 'Hall DE (Keynotes)');
      expect(v.room('Salt Palace | Level 1 | Hall DE')?.id, 'l1-hall-de');
      expect(v.offsiteVenue('offsite-hotel')?.walkMinutes, 4);
      expect(v.level('L2')?.shortName, 'L2');
    });

    test('info parses links and emergency text', () {
      final info = ConferenceInfo.fromJson({
        'wifi': {'network': 'KubeCon', 'password': 'p'},
        'emergency': 'Dial 911',
        'links': [
          {'title': 'Schedule', 'url': 'https://example.com'},
          {'title': 'No url'},
        ],
      });
      expect(info.wifi, 'KubeCon / p');
      expect(info.links, hasLength(1));
    });
  });

  group('time', () {
    test('default day is today during the conference', () {
      expect(defaultDayIndex(DateTime.utc(2026, 11, 11, 18)), 2);
      // 11 PM MST on Nov 9 is already Nov 10 in UTC, still day 0 locally.
      expect(defaultDayIndex(DateTime.utc(2026, 11, 10, 6)), 0);
      expect(defaultDayIndex(DateTime.utc(2026, 10, 1)), 0);
      expect(defaultDayIndex(DateTime.utc(2026, 12, 1)), 3);
    });
  });

  group('bundled data', () {
    Object? load(String name) =>
        jsonDecode(File('assets/data/$name').readAsStringSync());

    test(
      'every session room resolves to the venue map or an off-site venue',
      () {
        final schedule = ScheduleData.fromJson(load('sessions.json'));
        final venue = Venue.fromJson(load('venue.json'));
        expect(schedule.sessions, isNotEmpty);
        expect(venue.levels, isNotEmpty);
        final unresolved = schedule.sessions
            .where((s) => resolveLocation(venue, s.roomId) is UnknownLocation)
            .map((s) => s.roomId)
            .toSet();
        expect(unresolved, isEmpty);
      },
    );

    test('every venue room is on a known level and has directions', () {
      final venue = Venue.fromJson(load('venue.json'));
      final levelIds = venue.levels.map((l) => l.id).toSet();
      for (final r in venue.rooms) {
        expect(levelIds, contains(r.levelId), reason: r.id);
        expect(r.directions, isNotEmpty, reason: r.id);
        expect(r.x + r.w, lessThanOrEqualTo(1000.5), reason: r.id);
        expect(r.y + r.h, lessThanOrEqualTo(600.5), reason: r.id);
      }
    });

    test('happenings and info parse', () {
      expect(Happening.listFromJson(load('happenings.json')), isNotEmpty);
      expect(ConferenceInfo.fromJson(load('info.json')).links, isNotEmpty);
    });
  });
}
