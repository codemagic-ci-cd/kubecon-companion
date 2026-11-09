import 'package:flutter/material.dart';

import '../data/agenda_link.dart';
import '../services/web_url.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../widgets/agenda_share.dart';

import 'expo_screen.dart';
import 'map_screen.dart';
import 'now_screen.dart';
import 'saved_screen.dart';
import 'schedule_screen.dart';

/// Bottom navigation tab indexes.
abstract final class HomeTabs {
  static const schedule = 0;
  static const map = 1;
  static const now = 2;
  static const expo = 3;
  static const saved = 4;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0, this.pendingAgenda});
  final int initialTab;

  /// Agenda payload from a shared link (web `?agenda=`), offered for import
  /// after the first frame.
  final String? pendingAgenda;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialTab;
  AppState? _app;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.read(context);
    if (!identical(app, _app)) {
      _app?.mapFocus.removeListener(_onMapFocus);
      _app = app..mapFocus.addListener(_onMapFocus);
    }
  }

  @override
  void dispose() {
    _app?.mapFocus.removeListener(_onMapFocus);
    super.dispose();
  }

  /// "Show on map" from anywhere: close pushed screens and switch to Map,
  /// which then selects the room.
  void _onMapFocus() {
    if (_app?.mapFocus.value == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_index != HomeTabs.map) setState(() => _index = HomeTabs.map);
  }

  @override
  void initState() {
    super.initState();
    final payload = widget.pendingAgenda;
    if (payload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Strip it first so a reload never offers the same import again.
        removeQueryParam(kAgendaParam);
        if (!mounted) return;
        await confirmAgendaImport(context, AppScope.of(context), payload);
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
      onDestinationSelected: (i) => setState(() => _index = i),
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
