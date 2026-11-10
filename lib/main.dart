import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/agenda_link.dart';
import 'data/spot_link.dart';
import 'screens/home_shell.dart';
import 'services/incoming_links.dart';
import 'services/live_data_source.dart';
import 'services/notification_service.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'theme/brand.dart';
import 'widgets/link_router.dart';
import 'data/session_link.dart';
import 'services/history_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final live = createLiveDataSource();
  // A newer copy saved by an earlier refresh (native disk cache) is used
  // when there is one; startup never waits for the network.
  final data = ConferenceData.load(null, live);
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Storage blocked (e.g. some private browsing modes): settings stay in
    // memory for this session.
  }
  final state = AppState(
    data: await data,
    prefs: prefs,
    notifications: createNotificationService(),
    clockOffset: demoClockOffset(Uri.base),
    live: live,
  );
  // Web: the app keeps browser back/forward in step with its pages itself,
  // so Flutter's single-entry history handling is switched off.
  final history = browserHistory();
  if (history != null) setUrlStrategy(null);
  final agenda = agendaParam(Uri.base);
  final spot = agenda == null ? spotParamFrom(Uri.base) : null;
  final session = agenda == null && spot == null
      ? sessionParamFrom(Uri.base)
      : null;
  runApp(
    KubeConApp(
      state: state,
      // A shared agenda link lands on Saved, where the import ends up; a
      // shared spot on the Map.
      initialTab: agenda != null
          ? HomeTabs.saved
          : spot != null
          ? HomeTabs.map
          : initialTabFor(Uri.base),
      pendingAgenda: agenda,
      pendingSpot: spot,
      pendingSession: session,
      links: incomingLinks(),
      historySync: history == null ? null : HistorySync(history),
    ),
  );
  // Descriptions and bios (details.json) are not needed for the first screen:
  // fetch them once it is up, so slow networks show the schedule sooner.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(state.loadDetails());
    unawaited(state.loadSponsors());
    // Native apps can run for days on an old install: check for newer
    // data once up. The web app is already served fresh.
    if (!kIsWeb) {
      Future.delayed(const Duration(seconds: 3), state.autoRefresh);
    }
  });
  unawaited(state.start());
}

/// `?now=2026-11-10T12:40` (venue time) shifts the app clock for demos.
Duration demoClockOffset(Uri uri) {
  final raw = uri.queryParameters['now'];
  if (raw == null || raw.isEmpty) return Duration.zero;
  final hasOffset = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(raw);
  final target = DateTime.tryParse(hasOffset ? raw : '$raw-07:00');
  if (target == null) return Duration.zero;
  return target.toUtc().difference(DateTime.now().toUtc());
}

/// `?agenda=a1.…` from a shared agenda link (web).
String? agendaParam(Uri uri) {
  final v = uri.queryParameters[kAgendaParam];
  return v == null || v.isEmpty ? null : v;
}

/// `?tab=map|now|expo|saved` opens a tab directly (used by PWA shortcuts).
int initialTabFor(Uri uri) => switch (uri.queryParameters['tab']) {
  'map' => HomeTabs.map,
  'now' => HomeTabs.now,
  'expo' => HomeTabs.expo,
  'saved' => HomeTabs.saved,
  _ => HomeTabs.schedule,
};

class KubeConApp extends StatelessWidget {
  const KubeConApp({
    super.key,
    required this.state,
    this.home,
    this.initialTab = 0,
    this.pendingAgenda,
    this.pendingSpot,
    this.pendingSession,
    this.links,
    this.historySync,
  });
  final AppState state;
  final Widget? home;
  final int initialTab;

  /// Agenda payload from the launch URL, offered for import once up.
  final String? pendingAgenda;

  /// Spot payload (`?at=`) from the launch URL, pinned on the map once up.
  final String? pendingSpot;

  /// Session id from a shared session link (web `?session=`).
  final String? pendingSession;

  /// Links opening the native app: shared agendas and spots.
  final Stream<Uri>? links;

  /// Web: browser back/forward for pushed pages.
  final HistorySync? historySync;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'KubeCon Companion',
        debugShowCheckedModeBanner: false,
        // Let mouse and trackpad drags scroll horizontal rows (map level
        // chips, step pager) in desktop browsers, not only touch.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
        ),
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: state.themeMode,
        navigatorObservers: [?historySync],
        home:
            home ??
            _withLinks(
              HomeShell(
                initialTab: initialTab,
                pendingAgenda: pendingAgenda,
                pendingSpot: pendingSpot,
                pendingSession: pendingSession,
              ),
            ),
      ),
    ),
  );

  Widget _withLinks(Widget child) {
    final links = this.links;
    return links == null ? child : LinkRouter(links: links, child: child);
  }
}
