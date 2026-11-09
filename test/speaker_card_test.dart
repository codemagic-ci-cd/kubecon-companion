import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/models.dart';
import 'package:kubecon_companion/main.dart';
import 'package:kubecon_companion/services/notification_service.dart';
import 'package:kubecon_companion/state/app_state.dart';
import 'package:kubecon_companion/theme/brand.dart';
import 'package:kubecon_companion/widgets/speaker_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

final _bio = List.filled(12, 'Maintains open source things.').join(' ');

Speaker _speaker() => Speaker.fromJson({
  'name': 'Grace Example',
  'title': 'Maintainer',
  'company': 'Example Co',
  'bio': _bio,
  'photo': 'https://cdn.example.com/grace.jpg',
  'links': {
    'x': '@gracex',
    'github': 'https://github.com/grace-gh',
    'linkedin': 'https://www.linkedin.com/in/grace/',
    'bluesky': 'https://bsky.app/profile/grace.bsky.social',
    'website': 'https://www.linkedin.com/in/grace/',
  },
});

void main() {
  test('speakerLinks normalises handles and URLs, drops duplicates', () {
    final links = speakerLinks(_speaker());
    expect(links.map((l) => l.kind), ['x', 'github', 'linkedin', 'bluesky']);
    expect(links[0].url, 'https://x.com/gracex');
    expect(links[0].label, '@gracex');
    expect(links[1].url, 'https://github.com/grace-gh');
    expect(links[3].url, 'https://bsky.app/profile/grace.bsky.social');
    expect(speakerHandles(_speaker()), contains('grace.bsky.social'));

    final site = speakerLinks(
      Speaker.fromJson({
        'name': 'A',
        'links': {'website': 'example.dev', 'x': 'javascript:alert(1)'},
      }),
    );
    expect(site.single.kind, 'website');
    expect(site.single.url, 'https://example.dev');
    expect(speakerLinks(Speaker.fromJson({'name': 'B'})), isEmpty);
  });

  testWidgets('speaker card shows photo fallback, role, bio and chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: ListView(children: [SpeakerCard(speaker: _speaker())]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grace Example'), findsOneWidget);
    expect(find.text('Maintainer · Example Co'), findsOneWidget);
    // The network image fails in tests, so initials are shown instead.
    expect(find.text('GE'), findsOneWidget);
    expect(find.text('X @gracex'), findsOneWidget);
    expect(find.text('GitHub @grace-gh'), findsOneWidget);
    expect(find.text('LinkedIn'), findsOneWidget);
    expect(find.text('Bluesky @grace.bsky.social'), findsOneWidget);

    Text bio() => tester.widget<Text>(find.text(_bio));
    expect(bio().maxLines, 3);
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(bio().maxLines, isNull);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('schedule search matches speaker names and handles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      data: ConferenceData(
        schedule: testSchedule(),
        venue: testVenue(),
        happenings: testHappenings(),
        info: ConferenceInfo.fromJson({}),
      ),
      prefs: await SharedPreferences.getInstance(),
      notifications: NoopNotificationService(),
      clock: () => DateTime.utc(2026, 11, 10, 17),
    );
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(KubeConApp(state: state));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '@ada-gh');
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '@nobody-here');
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsNothing);

    // Names and companies come from schedule.json, so search works before
    // details.json has loaded (this state has no details).
    expect(state.details, isNull);
    await tester.enterText(find.byType(TextField), 'ada example');
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'example co');
    await tester.pumpAndSettle();
    expect(find.text('Scaling CI on Kubernetes'), findsOneWidget);
  });
}
