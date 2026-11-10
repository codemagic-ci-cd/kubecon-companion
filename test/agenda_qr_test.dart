import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/agenda_link.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/saved_screen.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/agenda_qr_scanner.dart';
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

/// A stand-in camera: one button per code it can "see".
QrCameraBuilder _fakeCamera(Map<String, String> codes) =>
    (context, onCode) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in codes.entries)
          TextButton(onPressed: () => onCode(e.value), child: Text(e.key)),
      ],
    );

Future<void> _openScanner(
  WidgetTester tester,
  AppState app,
  Map<String, String> codes,
) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    KubeConApp(
      state: app,
      home: SavedScreen(scannerCamera: _fakeCamera(codes)),
    ),
  );
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan agenda QR'));
  await tester.pumpAndSettle();
  expect(find.byType(AgendaQrScanner), findsOneWidget);
}

void main() {
  group('agendaPayloadFromQr', () {
    final payload = encodeAgenda(['w1', 'k1']);

    test('accepts share links, links without scheme and bare payloads', () {
      expect(agendaPayloadFromQr(agendaLink(['w1', 'k1'])), payload);
      expect(
        agendaPayloadFromQr('kubecon.codemagic.app/?agenda=$payload'),
        payload,
      );
      expect(agendaPayloadFromQr('  $payload\n'), payload);
    });

    test('rejects other QR content', () {
      expect(agendaPayloadFromQr(null), isNull);
      expect(agendaPayloadFromQr(''), isNull);
      expect(agendaPayloadFromQr('https://codemagic.io'), isNull);
      expect(agendaPayloadFromQr('WIFI:S:kubecon;T:WPA;P:x;;'), isNull);
      expect(agendaPayloadFromQr('$kAppBaseUrl?at=v1.x'), isNull);
      // Right prefix, but it does not decode.
      expect(agendaPayloadFromQr('a1.%%%'), isNull);
      expect(agendaPayloadFromQr('$kAppBaseUrl?agenda=a1.%25%25'), isNull);
    });
  });

  group('scanner', () {
    testWidgets('an agenda QR closes the scanner and offers the import', (
      tester,
    ) async {
      final app = await _state();
      await _openScanner(tester, app, {
        'agenda': agendaLink(['w1', 'k1']),
      });
      await tester.tap(find.text('agenda'));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaQrScanner), findsNothing);
      expect(
        find.text('Import 2 sessions from a shared agenda?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(app.saved, {'w1', 'k1'});
    });

    testWidgets('a bare payload works too', (tester) async {
      final app = await _state();
      await _openScanner(tester, app, {
        'bare': encodeAgenda(['w1']),
      });
      await tester.tap(find.text('bare'));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaImportDialog), findsOneWidget);
    });

    testWidgets('other QR content says so and keeps scanning', (tester) async {
      final app = await _state();
      await _openScanner(tester, app, {
        'other': 'https://example.com',
        'agenda': agendaLink(['w1']),
      });
      await tester.tap(find.text('other'));
      await tester.pump();
      expect(find.text('Not an agenda QR'), findsOneWidget);
      expect(find.byType(AgendaQrScanner), findsOneWidget);
      // Then a real one still works.
      await tester.tap(find.text('agenda'));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaQrScanner), findsNothing);
      expect(find.byType(AgendaImportDialog), findsOneWidget);
    });

    testWidgets('closing the scanner imports nothing', (tester) async {
      final app = await _state();
      await _openScanner(tester, app, {
        'agenda': agendaLink(['w1']),
      });
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaQrScanner), findsNothing);
      expect(find.byType(AgendaImportDialog), findsNothing);
      expect(app.saved, isEmpty);
    });
  });
}
