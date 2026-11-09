import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/agenda_link.dart';
import 'screens/home_shell.dart';
import 'services/notification_service.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'theme/brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final data = ConferenceData.load();
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
  );
  final agenda = agendaParam(Uri.base);
  runApp(
    KubeConApp(
      state: state,
      // A shared agenda link lands on Saved, where the import ends up.
      initialTab: agenda == null ? initialTabFor(Uri.base) : 3,
      pendingAgenda: agenda,
    ),
  );
  // Descriptions and bios (details.json) are not needed for the first screen:
  // fetch them once it is up, so slow networks show the schedule sooner.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(state.loadDetails()),
  );
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

/// `?tab=map|now|saved` opens a tab directly (used by PWA shortcuts).
int initialTabFor(Uri uri) => switch (uri.queryParameters['tab']) {
  'map' => 1,
  'now' => 2,
  'saved' => 3,
  _ => 0,
};

class KubeConApp extends StatelessWidget {
  const KubeConApp({
    super.key,
    required this.state,
    this.home,
    this.initialTab = 0,
    this.pendingAgenda,
  });
  final AppState state;
  final Widget? home;
  final int initialTab;

  /// Agenda payload from the launch URL, offered for import once up.
  final String? pendingAgenda;

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
        home:
            home ??
            HomeShell(initialTab: initialTab, pendingAgenda: pendingAgenda),
      ),
    ),
  );
}
