import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/agenda_link.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/saved_screen.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/agenda_share.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<AppState> _state({List<String> saved = const []}) async {
  SharedPreferences.setMockInitialValues({'saved_sessions': saved});
  return AppState(
    data: ConferenceData(
      schedule: testSchedule(),
      venue: testVenue(),
      happenings: testHappenings(),
      info: ConferenceInfo.fromJson({}),
    ),
    prefs: await SharedPreferences.getInstance(),
    notifications: NoopNotificationService(),
    clock: () => DateTime.utc(2026, 11, 10, 17),
    details: testDetails(),
  );
}

Future<void> _pump(WidgetTester tester, AppState state, {Widget? home}) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KubeConApp(state: state, home: home));
  await tester.pumpAndSettle();
}

/// Real session ids from the bundled schedule, for realistic lengths.
List<String> _realIds() {
  final raw = jsonDecode(File('assets/data/schedule.json').readAsStringSync());
  final list = (raw is Map ? raw['sessions'] : raw) as List;
  return [for (final s in list) (s as Map)['id'] as String];
}

void main() {
  group('agenda payload', () {
    test('round-trips numeric, co- and other ids', () {
      final ids = [
        '1304040',
        '1202489',
        'co-1268398',
        'co-1229385',
        '1382533',
        't1',
        'weird id/ü',
      ];
      final payload = encodeAgenda(ids);
      expect(payload, startsWith('a1.'));
      expect(payload, matches(RegExp(r'^a1\.[A-Za-z0-9_-]*$')));
      expect(decodeAgenda(payload)!.toSet(), ids.toSet());
    });

    test('dedupes, ignores order and handles empty', () {
      expect(
        encodeAgenda(['1304040', '1202489', '1304040']),
        encodeAgenda(['1202489', '1304040']),
      );
      expect(decodeAgenda(encodeAgenda(const [])), isEmpty);
    });

    test('ids that would not round-trip as numbers stay exact', () {
      final ids = ['0123', 'co-0', 'co-', '99999999999999999999'];
      expect(decodeAgenda(encodeAgenda(ids))!.toSet(), ids.toSet());
    });

    test('random real-world sets round-trip', () {
      final all = _realIds();
      final rnd = Random(7);
      for (var k = 0; k < 200; k++) {
        final pick = (all.toList()..shuffle(rnd)).take(rnd.nextInt(80));
        expect(decodeAgenda(encodeAgenda(pick))!.toSet(), pick.toSet());
      }
    });

    test('garbage never throws and returns null', () {
      for (final bad in [
        '',
        'a1',
        'a2.AAAA',
        'a1.!!!!',
        'a1.%%%',
        'a1.gICAgICAgICA', // overlong varint
        'a1.Bw', // count 7, no items
        'a1.AQA', // zero delta
        'a1.AAAB', // string section: count 1, no bytes
        'a1.AAABBf__', // invalid UTF-8
      ]) {
        expect(decodeAgenda(bad), isNull, reason: bad);
      }
      final rnd = Random(1);
      for (var k = 0; k < 500; k++) {
        final bytes = List.generate(rnd.nextInt(20), (_) => rnd.nextInt(256));
        final p = 'a1.${base64Url.encode(bytes).replaceAll('=', '')}';
        expect(() => decodeAgenda(p), returnsNormally);
      }
    });

    test('missing trailing sections count as empty', () {
      // One numeric id (5), no co- or other section.
      expect(decodeAgenda('a1.AQU'), ['5']);
    });

    test('links stay short enough for a scannable QR', () {
      final all = _realIds()..shuffle(Random(3));
      final lengths = {
        for (final n in [10, 30, 60]) n: agendaLink(all.take(n)).length,
      };
      // ignore: avoid_print
      print('agenda link length by session count: $lengths');
      expect(lengths[30], lessThan(200));
    });

    test('payload is extracted from links and bare text', () {
      final p = encodeAgenda(['1304040']);
      expect(agendaPayloadFrom(agendaLink(['1304040'])), p);
      expect(agendaPayloadFrom('kubecon.codemagic.app/?agenda=$p&now=x'), p);
      expect(agendaPayloadFrom('  $p '), p);
      expect(agendaPayloadFrom('https://kubecon.codemagic.app/'), isNull);
      expect(agendaPayloadFrom(''), isNull);
    });

    test('launch URL param', () {
      expect(agendaParam(Uri.parse('https://x/?agenda=a1.AQU')), 'a1.AQU');
      expect(agendaParam(Uri.parse('https://x/?agenda=')), isNull);
      expect(agendaParam(Uri.parse('https://x/get/')), isNull);
    });
  });

  group('import merge', () {
    test('adds known unsaved ids only, never removes', () async {
      final app = await _state(saved: ['t1']);
      expect(app.importableSessions(['t1', 'w1', 'nope']).map((s) => s.id), [
        'w1',
      ]);
      final added = await app.importSaved(['t1', 'w1', 'k1', 'nope']);
      expect(added, 2);
      expect(app.saved, {'t1', 'w1', 'k1'});
      expect(app.isReminderOn('w1'), isTrue);
      expect(app.prefs!.getStringList('saved_sessions')!.toSet(), {
        't1',
        'w1',
        'k1',
      });
      expect(await app.importSaved(['t1', 'nope']), 0);
      expect(app.saved, {'t1', 'w1', 'k1'});
    });
  });

  group('widgets', () {
    testWidgets('share sheet shows a QR for the agenda link', (tester) async {
      final app = await _state(saved: ['t1', 'w1']);
      await _pump(tester, app, home: const SavedScreen());
      await tester.tap(find.byTooltip('Share my agenda'));
      await tester.pumpAndSettle();
      expect(find.text('Share my agenda'), findsWidgets);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr, isNotNull);
      final link = agendaLink(['t1', 'w1']);
      expect(find.text(link), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.textContaining('2 saved sessions'), findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(copied, link);
      // Feedback lives on the button: a snackbar would sit behind the sheet.
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copy link'), findsOneWidget);
    });

    testWidgets('copy failure is reported on the button', (tester) async {
      final app = await _state(saved: ['t1']);
      await _pump(tester, app, home: const SavedScreen());
      await tester.tap(find.byTooltip('Share my agenda'));
      await tester.pumpAndSettle();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.setData'
            ? throw PlatformException(code: 'copy_fail')
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't copy"), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('share is disabled with nothing saved', (tester) async {
      final app = await _state();
      await _pump(tester, app, home: const SavedScreen());
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.qr_code_2),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('launch link offers import; Import adds', (tester) async {
      final app = await _state(saved: ['t1']);
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        KubeConApp(
          state: app,
          initialTab: 3,
          pendingAgenda: encodeAgenda(['t1', 'w1', 'k1', 'gone']),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Import 2 sessions from a shared agenda?'),
        findsOneWidget,
      );
      expect(find.text('Session w1'), findsWidgets);
      expect(find.textContaining('1 already in your Saved'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(app.saved, {'t1', 'w1', 'k1'});
      expect(find.text('Added 2 sessions to Saved.'), findsOneWidget);
    });

    testWidgets('Cancel leaves saved untouched', (tester) async {
      final app = await _state(saved: ['t1']);
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        KubeConApp(state: app, pendingAgenda: encodeAgenda(['w1'])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AgendaImportDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.saved, {'t1'});
    });

    testWidgets('paste link from the Saved menu', (tester) async {
      final app = await _state();
      await _pump(tester, app, home: const SavedScreen());
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import agenda link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('agenda-link-field')),
        'not a link',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('That does not look like an agenda link.'), findsOne);
      await tester.enterText(
        find.byKey(const ValueKey('agenda-link-field')),
        agendaLink(['w1']),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Import 1 session from a shared agenda?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(app.saved, {'w1'});
    });
  });
}
