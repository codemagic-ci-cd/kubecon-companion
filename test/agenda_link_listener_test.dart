import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/agenda_link.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/agenda_link_listener.dart';
import 'package:kubecon_companion/widgets/agenda_share.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<AppState> _state() async {
  SharedPreferences.setMockInitialValues({});
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

Future<void> _pump(WidgetTester tester, AppState app, Stream<Uri> links) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KubeConApp(state: app, links: links));
}

void main() {
  group('agendaFromLink', () {
    test('reads the agenda of a share link', () {
      final link = agendaLink(['w1']);
      expect(agendaFromLink(Uri.parse(link)), encodeAgenda(['w1']));
    });

    test('ignores links without an agenda', () {
      expect(agendaFromLink(Uri.parse(kAppBaseUrl)), isNull);
      expect(agendaFromLink(Uri.parse('${kAppBaseUrl}get/')), isNull);
      expect(agendaFromLink(Uri.parse('$kAppBaseUrl?agenda=')), isNull);
      expect(agendaFromLink(Uri.parse('$kAppBaseUrl?tab=map')), isNull);
    });

    test('never throws on a malformed query', () {
      final uri = Uri.parse('$kAppBaseUrl?agenda=%zz&x=%');
      expect(() => agendaFromLink(uri), returnsNormally);
    });
  });

  group('native links', () {
    testWidgets('launch link offers the import once', (tester) async {
      final app = await _state();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await _pump(tester, app, links.stream);
      final uri = Uri.parse(agendaLink(['w1', 'k1']));
      // Reported twice around a cold start: offered once.
      links
        ..add(uri)
        ..add(uri);
      await tester.pumpAndSettle();
      expect(find.byType(AgendaImportDialog), findsOneWidget);
      expect(
        find.text('Import 2 sessions from a shared agenda?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(app.saved, {'w1', 'k1'});
      expect(find.byType(AgendaImportDialog), findsNothing);
    });

    testWidgets('a link while running offers its import', (tester) async {
      final app = await _state();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await _pump(tester, app, links.stream);
      await tester.pumpAndSettle();
      expect(find.byType(AgendaImportDialog), findsNothing);
      links.add(Uri.parse(agendaLink(['w1'])));
      await tester.pumpAndSettle();
      expect(find.text('Import 1 session from a shared agenda?'), findsOne);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.saved, isEmpty);
    });

    testWidgets('other links and link errors are ignored', (tester) async {
      final app = await _state();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await _pump(tester, app, links.stream);
      links
        ..add(Uri.parse(kAppBaseUrl))
        ..add(Uri.parse('${kAppBaseUrl}get/'))
        ..addError(Exception('no plugin'));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaImportDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a broken agenda link says so', (tester) async {
      final app = await _state();
      final links = StreamController<Uri>.broadcast();
      addTearDown(links.close);
      await _pump(tester, app, links.stream);
      links.add(Uri.parse('$kAppBaseUrl?agenda=a1.%25%25'));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaImportDialog), findsNothing);
      expect(find.text('That agenda link is not valid.'), findsOneWidget);
    });
  });
}
