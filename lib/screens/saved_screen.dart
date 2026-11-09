import 'package:flutter/material.dart';

import '../data/venue_time.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../widgets/agenda_share.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/calendar_export.dart';
import '../widgets/common.dart';
import '../widgets/session_tile.dart';

/// Your starred sessions, grouped by day, with past ones at the bottom.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = app.now;
    final saved = app.savedSessions;
    final upcoming = saved.where((s) => s.end.isAfter(now)).toList();
    final past = saved.where((s) => !s.end.isAfter(now)).toList();

    final rows = <Widget>[];
    DateTime? lastDay;
    for (final s in upcoming) {
      final d = venueDay(s.start);
      if (lastDay == null || !sameDay(d, lastDay)) {
        rows.add(SectionTitle(fmtDayLong(d, isDay: true)));
        lastDay = d;
      }
      rows.add(SessionTile(session: s));
    }
    if (past.isNotEmpty) {
      rows.add(const SectionTitle('Already happened'));
      rows.addAll(
        past.map(
          (s) => Opacity(
            opacity: 0.55,
            child: SessionTile(session: s, showDay: true),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(),
        actions: [
          IconButton(
            tooltip: 'Share my agenda',
            icon: const Icon(Icons.qr_code_2),
            onPressed: saved.isEmpty
                ? null
                : () => AgendaShareSheet.show(context, saved.map((s) => s.id)),
          ),
          const SettingsAction(),
          _SavedMenu(app: app, hasSaved: saved.isNotEmpty),
        ],
      ),
      body: saved.isEmpty
          ? const EmptyState(
              icon: Icons.star_outline_rounded,
              title: 'No saved sessions yet',
              message: 'Tap the star on any session to build your personal agenda. Saved sessions get a reminder 10 minutes before they start.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: rows,
            ),
    );
  }
}

enum _SavedMenuItem { share, calendar, import }

/// Overflow menu: share, export to calendar, import a shared agenda link.
class _SavedMenu extends StatelessWidget {
  const _SavedMenu({required this.app, required this.hasSaved});
  final AppState app;
  final bool hasSaved;

  Future<void> _import(BuildContext context) async {
    final payload = await showDialog<String>(
      context: context,
      builder: (_) => const PasteAgendaDialog(),
    );
    if (payload != null && context.mounted) {
      await confirmAgendaImport(context, app, payload);
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<_SavedMenuItem>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert),
    onSelected: (item) => switch (item) {
      _SavedMenuItem.share => AgendaShareSheet.show(
        context,
        app.savedSessions.map((s) => s.id),
      ),
      _SavedMenuItem.calendar => exportToCalendar(
        context,
        app,
        app.savedSessions,
      ),
      _SavedMenuItem.import => _import(context),
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: _SavedMenuItem.share,
        enabled: hasSaved,
        child: const ListTile(
          leading: Icon(Icons.qr_code_2),
          title: Text('Share my agenda'),
        ),
      ),
      PopupMenuItem(
        value: _SavedMenuItem.calendar,
        enabled: hasSaved,
        child: const ListTile(
          leading: Icon(Icons.event_outlined),
          title: Text('Export saved to calendar'),
        ),
      ),
      const PopupMenuItem(
        value: _SavedMenuItem.import,
        child: ListTile(
          leading: Icon(Icons.download_outlined),
          title: Text('Import agenda link'),
        ),
      ),
    ],
  );
}
