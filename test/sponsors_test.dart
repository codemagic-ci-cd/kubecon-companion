import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/data/sponsors.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/screens/expo_screen.dart';
import 'package:kubecon_companion/screens/home_shell.dart';
import 'package:kubecon_companion/screens/map_screen.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/widgets/sponsor_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

final sponsorsJson = <String, dynamic>{
  'sponsors': [
    {
      'id': 'example-co',
      'name': 'Example Co',
      'tier': 'Gold',
      'booth': '115',
      'hall': 'Halls A-C',
      'roomId': 'l1-hall-de',
      'website': 'https://example.com/',
      'description': 'Example Co builds observability pipelines for clusters.',
      'tags': ['Observability'],
    },
    {
      'id': 'acme-cloud',
      'name': 'Acme Cloud',
      'tier': 'Diamond',
      'booth': '145 + 151',
      'hall': 'Halls A-C',
      'roomId': 'l1-hall-de',
      'description': 'Managed Kubernetes.',
      'tags': ['Platform Engineering', 'Security'],
    },
    {
      'id': 'example-labs',
      'name': 'Example Labs',
      'tier': 'Silver',
      'booth': '210',
      'hall': 'Halls 1-5',
      'roomId': 'not-on-map',
    },
    {'id': 'example-dev', 'name': 'Example Dev', 'tier': 'Start-Up'},
    {'id': 'example-news', 'name': 'Example News', 'tier': 'Media Partner'},
    {'name': '  ', 'tier': 'Gold'},
    'not a sponsor',
  ],
};

final showcase = <String, dynamic>{
  'id': 'showcase-10',
  'title': 'Solutions Showcase Open',
  'start': '2026-11-10T10:45:00-07:00',
  'end': '2026-11-10T17:15:00-07:00',
  'kind': 'expo',
  'roomId': 'l1-hall-de',
  'description': 'Sponsor booths and the Project Pavilion.',
};

Future<AppState> _state({List<Sponsor>? sponsors}) async {
  SharedPreferences.setMockInitialValues({});
  return AppState(
    data: ConferenceData(
      schedule: testSchedule(),
      venue: testVenue(),
      happenings: Happening.listFromJson({
        'items': [...happeningsJson['items'] as List, showcase],
      }),
      info: ConferenceInfo.fromJson({}),
      officialMap: testOfficialMap(),
    ),
    prefs: await SharedPreferences.getInstance(),
    notifications: NoopNotificationService(),
    // 10:00 AM MST on Tue Nov 10.
    clock: () => DateTime.utc(2026, 11, 10, 17),
    details: testDetails(),
    sponsors: sponsors ?? Sponsor.listFromJson(sponsorsJson),
  );
}

Future<void> _pump(WidgetTester tester, AppState state, {Widget? home}) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KubeConApp(state: state, home: home));
  await tester.pumpAndSettle();
}

/// Serves sponsors.json from memory, or fails.
class _Bundle extends CachingAssetBundle {
  _Bundle({this.fail = false});
  final bool fail;

  @override
  Future<ByteData> load(String key) async {
    if (fail || key != 'assets/data/sponsors.json') {
      throw FlutterError('Unable to load asset: $key');
    }
    final bytes = utf8.encode(jsonEncode(sponsorsJson));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  group('parsing', () {
    test('skips broken entries, sorts by tier then name', () {
      final list = Sponsor.listFromJson(sponsorsJson);
      expect(list.map((s) => s.name), [
        'Acme Cloud',
        'Example Co',
        'Example Labs',
        'Example Dev',
        'Example News',
      ]);
      final dev = list.firstWhere((s) => s.id == 'example-dev');
      expect(dev.booth, isNull);
      expect(dev.boothLabel, isNull);
      expect(dev.tags, isEmpty);
      expect(dev.description, '');
      expect(list.first.boothLabel, 'Booth 145 + 151 · Halls A-C');
      expect(list.first.boothNumbers, ['145', '151']);
      expect(Sponsor.listFromJson(null), isEmpty);
      expect(Sponsor.listFromJson({'sponsors': 'x'}), isEmpty);
      expect(Sponsor.listFromJson(sponsorsJson['sponsors']), hasLength(5));
    });

    test('bundled sponsors.json parses and every booth has a hall', () {
      final file = File('assets/data/sponsors.json');
      final list = Sponsor.listFromJson(jsonDecode(file.readAsStringSync()));
      expect(list.length, greaterThan(100));
      for (final s in list) {
        expect(sponsorTiers, contains(s.tier), reason: s.name);
        if (s.booth != null) {
          expect(s.hall, isNotNull, reason: s.name);
          expect(s.roomId, isNotNull, reason: s.name);
        }
      }
    });
  });

  group('search', () {
    final list = Sponsor.listFromJson(sponsorsJson);
    Sponsor byId(String id) => list.firstWhere((s) => s.id == id);

    test('matches name, booth, tag and description words', () {
      final co = byId('example-co');
      expect(sponsorMatch(co, 'example'), SponsorMatch.namePrefix);
      expect(sponsorMatch(co, 'EXAMPLECO'), SponsorMatch.namePrefix);
      expect(sponsorMatch(co, 'co'), SponsorMatch.name);
      expect(sponsorMatch(co, '115'), SponsorMatch.booth);
      expect(sponsorMatch(co, 'Booth 115'), SponsorMatch.booth);
      expect(sponsorMatch(co, '11'), SponsorMatch.none);
      expect(sponsorMatch(co, 'observ'), SponsorMatch.tag);
      expect(sponsorMatch(co, 'pipelines'), SponsorMatch.description);
      expect(sponsorMatch(co, 'ipelines'), SponsorMatch.none);
      expect(sponsorMatch(co, ''), SponsorMatch.none);
      expect(sponsorMatch(byId('acme-cloud'), '151'), SponsorMatch.booth);
    });

    test('filter by query and tier, rank best first', () {
      expect(filterSponsors(list, ''), hasLength(5));
      expect(
        filterSponsors(list, 'example', tier: 'Gold').single.id,
        'example-co',
      );
      expect(filterSponsors(list, 'security').single.id, 'acme-cloud');
      // Name match before the description match.
      expect(rankSponsors(list, 'kubernetes').map((s) => s.id), ['acme-cloud']);
      expect(rankSponsors(list, 'co').first.id, 'example-co');
      expect(hasStrongSponsorMatch(list, 'acme'), isTrue);
      expect(hasStrongSponsorMatch(list, 'security'), isFalse);
    });

    test('expo hours', () {
      final hs = Happening.listFromJson({
        'items': [showcase],
      });
      DateTime at(int h, [int m = 0]) => DateTime.utc(2026, 11, 10, h + 7, m);
      expect(
        expoHours(hs, at(9))!.title,
        'Solutions Showcase opens today 10:45 AM – 5:15 PM',
      );
      final open = expoHours(hs, at(12))!;
      expect(open.title, 'Solutions Showcase open now until 5:15 PM');
      expect(open.isOpen, isTrue);
      expect(
        expoHours(hs, DateTime.utc(2026, 11, 9, 20))!.title,
        'Solutions Showcase opens Tue 10 10:45 AM – 5:15 PM',
      );
      expect(expoHours(hs, at(18)), isNull);
    });
  });

  group('Expo tab', () {
    testWidgets('lists sponsors by tier with hours, search and tier chips', (
      tester,
    ) async {
      final app = await _state();
      await _pump(
        tester,
        app,
        home: const HomeShell(initialTab: HomeTabs.expo),
      );

      expect(find.text('Expo'), findsOneWidget);
      expect(
        find.text('Solutions Showcase opens today 10:45 AM – 5:15 PM'),
        findsOneWidget,
      );
      expect(find.text('Diamond · 1'), findsOneWidget);
      expect(find.text('Booth 115 · Halls A-C'), findsOneWidget);
      expect(find.text('All 5'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Example News'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('Media Partner · 1'), findsOneWidget);
      expect(find.text('No booth listed'), findsWidgets);

      await tester.enterText(find.byType(TextField), '210');
      await tester.pump();
      expect(find.byType(SponsorTile), findsOneWidget);
      expect(find.text('Example Labs'), findsOneWidget);
      expect(find.text('1 sponsor'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'example');
      await tester.pump();
      await tester.tap(find.text('Gold 1'));
      await tester.pump();
      expect(find.byType(SponsorTile), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No matching sponsors'), findsOneWidget);
      await tester.tap(find.text('Clear search and filters'));
      await tester.pump();
      expect(find.text('All 5'), findsOneWidget);
      expect(find.text('Acme Cloud'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sheet shows booth; Show on map switches to the Map tab', (
      tester,
    ) async {
      final app = await _state();
      await _pump(
        tester,
        app,
        home: const HomeShell(initialTab: HomeTabs.expo),
      );

      await tester.tap(find.text('Example Co'));
      await tester.pumpAndSettle();
      expect(find.text('Gold sponsor'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      await tester.tap(find.text('Show on map'));
      await tester.pumpAndSettle();

      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, HomeTabs.map);
      expect(app.mapFocus.value, isNull);
      // The map's room sheet opened on the hall.
      expect(
        find.descendant(
          of: find.byType(RoomSheet),
          matching: find.text('Hall DE (Keynotes)'),
        ),
        findsWidgets,
      );
    });

    testWidgets('no Show on map when the room is not on the venue map', (
      tester,
    ) async {
      final app = await _state();
      await _pump(tester, app, home: const ExpoScreen(initialQuery: '210'));
      await tester.tap(find.text('Example Labs'));
      await tester.pumpAndSettle();
      expect(find.text('Booth 210 · Halls 1-5'), findsWidgets);
      expect(find.text('Show on map'), findsNothing);
    });

    testWidgets('bundled sponsors fit a 320px screen', (tester) async {
      final real = Sponsor.listFromJson(
        jsonDecode(File('assets/data/sponsors.json').readAsStringSync()),
      );
      final app = await _state(sponsors: real);
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        KubeConApp(
          state: app,
          home: const HomeShell(initialTab: HomeTabs.expo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ListView).last,
        const Offset(0, -3000),
        3000,
      );
      await tester.pumpAndSettle();
      final longest = real.reduce(
        (a, b) => a.name.length >= b.name.length ? a : b,
      );
      await tester.enterText(find.byType(TextField), longest.name);
      await tester.pump();
      await tester.tap(find.byType(SponsorTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(SponsorSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state', (tester) async {
      final app = await _state(sponsors: const []);
      await _pump(tester, app, home: const ExpoScreen());
      expect(find.text('No sponsors yet'), findsOneWidget);
    });

    testWidgets('failed load offers a retry that loads', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState(
        data: ConferenceData(
          schedule: testSchedule(),
          venue: testVenue(),
          happenings: const [],
          info: ConferenceInfo.fromJson({}),
        ),
        prefs: await SharedPreferences.getInstance(),
        notifications: NoopNotificationService(),
        clock: () => DateTime.utc(2026, 11, 10, 17),
      );
      expect(app.sponsorsStatus, DetailsStatus.loading);
      await tester.runAsync(() => app.loadSponsors(_Bundle(fail: true)));
      expect(app.sponsorsStatus, DetailsStatus.failed);
      await _pump(tester, app, home: const ExpoScreen());
      expect(find.text('Could not load sponsors'), findsOneWidget);

      await tester.runAsync(() => app.loadSponsors(_Bundle()));
      await tester.pumpAndSettle();
      expect(app.sponsorsStatus, DetailsStatus.loaded);
      expect(find.text('Acme Cloud'), findsOneWidget);
    });
  });

  group('schedule search', () {
    testWidgets('shows sponsors above talks; See all opens Expo', (
      tester,
    ) async {
      final app = await _state();
      await _pump(tester, app);

      // Speaker company search still finds talks.
      await tester.enterText(find.byType(TextField), 'example');
      await tester.pumpAndSettle();
      expect(find.text('Sponsors & booths'), findsOneWidget);
      expect(find.byType(SponsorTile), findsNWidgets(3));
      expect(find.text('Scaling CI on Kubernetes'), findsWidgets);
      expect(find.text('See all 4'), findsOneWidget);

      await tester.tap(find.text('See all 4'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpoScreen), findsOneWidget);
      expect(find.byType(SponsorTile), findsNWidgets(4));
      expect(find.text('4 sponsors'), findsOneWidget);
    });

    testWidgets('topic words alone do not add the sponsor section', (
      tester,
    ) async {
      final app = await _state();
      await _pump(tester, app);
      await tester.enterText(find.byType(TextField), 'security');
      await tester.pumpAndSettle();
      expect(find.text('Sponsors & booths'), findsNothing);

      await tester.enterText(find.byType(TextField), 'acme');
      await tester.pumpAndSettle();
      expect(find.text('Sponsors & booths'), findsOneWidget);
      expect(find.text('See all 1'), findsNothing);
      expect(find.text('No matching sessions'), findsOneWidget);
    });
  });
}
