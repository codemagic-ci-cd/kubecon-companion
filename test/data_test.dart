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
      expect(t1.hasPrerequisites, isTrue);
      expect(t1.prerequisites, isEmpty); // in details.json
      expect(t1.description, isEmpty);
      expect(t1.speakers.single.id, 'ada');
      expect(t1.speakers.single.role, 'Engineer · Example Co');
      expect(t1.speakers.single.links.github, 'ada-gh');
      expect(t1.speakers.single.bio, isNull);
      expect(t1.levelName, 'Beginner');
      expect(
        s.sessions.firstWhere((x) => x.id == 'k1').hasPrerequisites,
        false,
      );
    });

    test('details merge description, prerequisites and speaker bios', () {
      final d = testDetails();
      expect(d.sessions['t1']?.description, 'About t1');
      expect(d.speakers['ada']?.bio, 'Builds things.');
      final t1 = testSchedule().sessions
          .firstWhere((x) => x.id == 't1')
          .withDetails(d);
      expect(t1.description, 'About t1');
      expect(t1.prerequisites, ['Laptop with kind installed']);
      final ada = t1.speakers.single;
      expect(ada.name, 'Ada Example');
      expect(ada.bio, 'Builds things.');
      expect(ada.photo, 'https://cdn.example.com/ada.jpg');
      expect(ada.links.github, 'ada-gh');
      expect(ada.links.linkedin, 'https://www.linkedin.com/in/ada/');
      expect(ConferenceDetails.fromJson('junk').sessions, isEmpty);
    });

    test(
      'speaker ids and inline speakers resolve; unknown ids are skipped',
      () {
        final s = ScheduleData.fromJson({
          'speakers': {
            '0': {'name': 'Zero'},
            '1': 'junk',
          },
          'sessions': [
            {
              'id': 'a',
              'start': '2026-11-10T09:00:00-07:00',
              'speakers': [
                '0',
                '1',
                'missing',
                {'name': 'Inline Person'},
                null,
              ],
            },
          ],
        });
        final a = s.sessions.single;
        expect(a.speakers.map((p) => p.name), ['Zero', 'Inline Person']);
        expect(a.speakers.last.id, isNull);
        // Inline speakers have no details; merging leaves them alone.
        expect(
          a.withDetails(testDetails()).speakers.last.name,
          'Inline Person',
        );
      },
    );

    test('the older inline sessions.json shape still parses', () {
      final s = ScheduleData.fromJson({
        'sessions': [
          {
            'id': 'x',
            'start': '2026-11-10T09:00:00-07:00',
            'description': 'Inline',
            'prerequisites': ['Laptop'],
            'speakers': [
              {'name': 'Ada', 'bio': 'Bio'},
            ],
          },
        ],
      }).sessions.single;
      expect(s.description, 'Inline');
      expect(s.hasPrerequisites, isTrue);
      expect(s.speakers.single.bio, 'Bio');
      expect(s.withDetails(testDetails()).description, 'Inline');
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
        final schedule = ScheduleData.fromJson(load('schedule.json'));
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

    test('schedule.json and details.json parse and join', () {
      final schedule = ScheduleData.fromJson(load('schedule.json'));
      final details = ConferenceDetails.fromJson(load('details.json'));
      expect(schedule.sessions, hasLength(greaterThan(500)));
      expect(details.sessions, isNotEmpty);
      expect(details.speakers, isNotEmpty);
      // Every session with details is on the schedule, and every speaker
      // with details is used by a session.
      final ids = schedule.sessions.map((s) => s.id).toSet();
      expect(details.sessions.keys.where((k) => !ids.contains(k)), isEmpty);
      final speakerIds = {
        for (final s in schedule.sessions)
          for (final p in s.speakers) ?p.id,
      };
      expect(
        details.speakers.keys.where((k) => !speakerIds.contains(k)),
        isEmpty,
      );
      final withPrereqs = schedule.sessions.where((s) => s.hasPrerequisites);
      expect(withPrereqs, isNotEmpty);
      for (final s in withPrereqs) {
        expect(details.sessions[s.id]?.prerequisites, isNotEmpty, reason: s.id);
      }
      final full = schedule.sessions.map((s) => s.withDetails(details));
      expect(full.where((s) => s.description.isNotEmpty), isNotEmpty);
      expect(
        full.expand((s) => s.speakers).where((p) => p.bio != null),
        isNotEmpty,
      );
      expect(
        schedule.sessions.expand((s) => s.speakers).every((p) => p.bio == null),
        isTrue,
        reason: 'bios belong in details.json',
      );
    });

    test('happenings and info parse', () {
      expect(Happening.listFromJson(load('happenings.json')), isNotEmpty);
      expect(ConferenceInfo.fromJson(load('info.json')).links, isNotEmpty);
    });
  });
}
