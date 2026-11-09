import 'package:flutter/material.dart';

import '../data/venue_time.dart';
import '../state/app_scope.dart';
import '../widgets/app_bar_title.dart';
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
        actions: const [SettingsAction()],
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
