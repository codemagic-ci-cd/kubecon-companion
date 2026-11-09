import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/reminders.dart';

import 'fixtures.dart';

void main() {
  final venue = testVenue();
  final sessions = testSchedule().sessions;
  final happenings = testHappenings();
  final beforeConf = DateTime.utc(2026, 11, 9, 12);

  List<Reminder> build({
    DateTime? now,
    Set<String> saved = const {},
    Set<String> muted = const {},
    int max = 60,
  }) => buildReminders(
    sessions: sessions,
    happenings: happenings,
    venue: venue,
    now: now ?? beforeConf,
    saved: saved,
    muted: muted,
    max: max,
  );

  test('highlights notify 10 minutes early, deduplicated', () {
    final r = build();
    // Keynote block (happening), lunch (session + happening -> one), reception.
    expect(r.map((e) => e.title), ['Keynotes', 'Lunch', 'Reception']);
    expect(r[1].fireAt, DateTime.utc(2026, 11, 10, 19, 40));
    expect(r.last.body, contains('Example Hotel'));
  });

  test('individual keynote talks and facilities do not notify', () {
    final r = build();
    expect(r.any((e) => e.sessionId == 'k1'), isFalse);
    expect(r.any((e) => e.title == 'Quiet room'), isFalse);
  });

  test('saved sessions notify and ids are stable', () {
    final r = build(saved: {'t1', 'w1'});
    final t1 = r.singleWhere((e) => e.sessionId == 't1');
    expect(t1.personal, isTrue);
    expect(t1.title, 'Starting soon: Scaling CI on Kubernetes');
    expect(t1.body, contains('Room 250 A-C'));
    expect(t1.id, stableId('session|t1'));
    expect(stableId('session|t1'), stableId('session|t1'));
    expect(stableId('a'), isNot(stableId('b')));
    expect(r.where((e) => e.sessionId == 'w1'), hasLength(1));
  });

  test('only future reminders, soonest first, capped', () {
    final afterLunch = DateTime.utc(2026, 11, 10, 20);
    final r = build(now: afterLunch, saved: {'w1'});
    expect(r.map((e) => e.title), ['Reception', 'Starting soon: Session w1']);
    expect(build(max: 1), hasLength(1));
  });

  test('a muted saved session does not notify', () {
    final on = build(saved: {'t1'});
    expect(on.any((e) => e.sessionId == 't1'), isTrue);
    final off = build(saved: {'t1'}, muted: {'t1'});
    expect(off.any((e) => e.sessionId == 't1'), isFalse);
  });
}
