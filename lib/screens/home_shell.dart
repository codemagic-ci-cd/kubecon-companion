import 'package:flutter/material.dart';

import '../data/agenda_link.dart';
import '../services/web_url.dart';
import '../state/app_scope.dart';
import '../widgets/agenda_share.dart';

import 'map_screen.dart';
import 'now_screen.dart';
import 'saved_screen.dart';
import 'schedule_screen.dart';

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
        MapScreen(active: _index == 1),
        const NowScreen(),
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
          icon: Icon(Icons.star_outline_rounded),
          selectedIcon: Icon(Icons.star_rounded),
          label: 'Saved',
        ),
      ],
    ),
  );
}
