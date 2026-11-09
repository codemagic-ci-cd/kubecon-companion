import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  runApp(KubeConApp(state: state, initialTab: initialTabFor(Uri.base)));
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
  });
  final AppState state;
  final Widget? home;
  final int initialTab;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'KubeCon Companion',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: state.themeMode,
        home: home ?? HomeShell(initialTab: initialTab),
      ),
    ),
  );
}
