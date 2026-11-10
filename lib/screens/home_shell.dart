import 'package:flutter/material.dart';

import '../data/agenda_link.dart';
import '../data/session_link.dart';
import '../data/spot_link.dart';
import '../services/web_url.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../widgets/agenda_share.dart';
import '../widgets/link_router.dart' show openSessionLink, openSpotLink;

import 'expo_screen.dart';
import 'map_screen.dart';
import 'now_screen.dart';
import 'saved_screen.dart';
import 'schedule_screen.dart';
import '../services/analytics.dart';

const _tabNames = ['Schedule', 'Map', 'Now', 'Expo', 'Saved'];

/// Bottom navigation tab indexes.
abstract final class HomeTabs {
  static const schedule = 0;
  static const map = 1;
  static const now = 2;
  static const expo = 3;
  static const saved = 4;
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.initialTab = 0,
    this.pendingAgenda,
    this.pendingSpot,
    this.pendingSession,
  });
  final int initialTab;

  /// Agenda payload from a shared link (web `?agenda=`), offered for import
  /// after the first frame.
  final String? pendingAgenda;

  /// Spot payload from a shared spot link (web `?at=`), pinned on the map
  /// after the first frame.
  final String? pendingSpot;

  /// Session id from a shared session link (web `?session=`), opened after
  /// the first frame.
  final String? pendingSession;

  /// Goes back to the home page: the Schedule tab, with pushed screens closed.
  static void goHome(BuildContext context) {
    final state = context.findAncestorStateOfType<_HomeShellState>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    state?._select(HomeTabs.schedule);
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialTab;
  AppState? _app;

  void _select(int tab) {
    if (_index == tab) return;
    track(Events.tab, {'tab': _tabNames[tab]});
    setState(() => _index = tab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.read(context);
    if (!identical(app, _app)) {
      _app?.mapFocus.removeListener(_onMapFocus);
      _app?.spotFocus.removeListener(_onSpotFocus);
      _app = app
        ..mapFocus.addListener(_onMapFocus)
        ..spotFocus.addListener(_onSpotFocus);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _app?.mapFocus.removeListener(_onMapFocus);
    _app?.spotFocus.removeListener(_onSpotFocus);
    super.dispose();
  }

  /// A shared spot was opened: show it on the Map tab.
  void _onSpotFocus() {
    if (_app?.sharedSpot.value == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_index != HomeTabs.map) setState(() => _index = HomeTabs.map);
  }

  /// "Show on map" from anywhere: close pushed screens and switch to Map,
  /// which then selects the room.
  void _onMapFocus() {
    if (_app?.mapFocus.value == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_index != HomeTabs.map) setState(() => _index = HomeTabs.map);
  }

  /// Fetches the latest data when the app comes back after a while.
  late final _lifecycle = AppLifecycleListener(
    onResume: () => _app?.autoRefresh(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
    final payload = widget.pendingAgenda;
    if (payload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Strip it first so a reload never offers the same import again.
        removeQueryParam(kAgendaParam);
        if (!mounted) return;
        await confirmAgendaImport(context, AppScope.of(context), payload);
      });
    }
    final session = widget.pendingSession;
    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        removeQueryParam(kSessionParam);
        if (!mounted) return;
        openSessionLink(context, AppScope.read(context), session);
      });
    }
    final spot = widget.pendingSpot;
    if (spot != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        removeQueryParam(kSpotParam);
        if (!mounted) return;
        openSpotLink(context, AppScope.read(context), spot);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: [
        const ScheduleScreen(),
        MapScreen(active: _index == HomeTabs.map),
        const NowScreen(),
        const ExpoScreen(),
        const SavedScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: _select,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today),
          label: 'Schedule',
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Map',
        ),
        NavigationDestination(
          icon: Icon(Icons.bolt_outlined),
          selectedIcon: Icon(Icons.bolt),
          label: 'Now',
        ),
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront),
          label: 'Expo',
        ),
        NavigationDestination(
          icon: Icon(Icons.star_outline_rounded),
          selectedIcon: Icon(Icons.star_rounded),
          label: 'Saved',
        ),
      ],
    ),
  );
}
