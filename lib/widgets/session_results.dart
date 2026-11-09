import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/venue_time.dart';
import '../theme/brand.dart';
import 'common.dart';
import 'session_tile.dart';

/// Rows for a lazy session list: section titles, time headers and sessions.
sealed class SessionListRow {}

class _SectionRow extends SessionListRow {
  _SectionRow(this.title, {this.icon});
  final String title;
  final IconData? icon;
}

class _TimeRow extends SessionListRow {
  _TimeRow(this.label);
  final String label;
}

class _SessionRow extends SessionListRow {
  _SessionRow(this.session);
  final Session session;
}

class _EndedToggleRow extends SessionListRow {
  _EndedToggleRow(this.count, this.label);
  final int count;
  final String label;
}

/// Adds sessions to [rows] with a time header whenever the label changes.
void addTimedRows(
  List<SessionListRow> rows,
  Iterable<Session> sessions,
  String Function(Session) label,
) {
  String? last;
  for (final s in sessions) {
    final l = label(s);
    if (l != last) {
      rows.add(_TimeRow(l));
      last = l;
    }
    rows.add(_SessionRow(s));
  }
}

/// Orders by start time, then title.
int bySessionStart(Session a, Session b) {
  final c = a.start.compareTo(b.start);
  return c != 0 ? c : a.title.compareTo(b.title);
}

/// Upcoming first, then what's on now, then (collapsed) what has ended.
List<SessionListRow> upcomingFirstRows({
  required List<Session> sessions,
  required DateTime now,
  required bool expandedEnded,
  required String Function(Session) timeLabel,
  required String endedLabel,
}) {
  final upcoming = sessions.where((s) => !s.start.isBefore(now)).toList()
    ..sort(bySessionStart);
  final live =
      sessions
          .where((s) => s.start.isBefore(now) && s.end.isAfter(now))
          .toList()
        ..sort((a, b) => a.end.compareTo(b.end));
  final ended = sessions.where((s) => !s.end.isAfter(now)).toList()
    ..sort(bySessionStart);

  final rows = <SessionListRow>[];
  if (upcoming.isNotEmpty) {
    rows.add(_SectionRow('Coming up', icon: Icons.upcoming_outlined));
    addTimedRows(rows, upcoming, timeLabel);
  }
  if (live.isNotEmpty) {
    rows.add(_SectionRow('Happening now', icon: Icons.sensors));
    for (final s in live) {
      rows.add(_SessionRow(s));
    }
  }
  if (ended.isNotEmpty) {
    rows.add(_EndedToggleRow(ended.length, endedLabel));
    if (expandedEnded) addTimedRows(rows, ended, timeLabel);
  }
  return rows;
}

/// Renders [rows] lazily, with an optional [header] on top.
class SessionRowsList extends StatelessWidget {
  const SessionRowsList({
    super.key,
    required this.rows,
    this.header,
    this.expandedEnded = false,
    this.onToggleEnded,
  });

  final List<SessionListRow> rows;
  final Widget? header;
  final bool expandedEnded;
  final VoidCallback? onToggleEnded;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final h = header == null ? 0 : 1;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length + h,
      itemBuilder: (context, i) {
        if (h == 1 && i == 0) return header!;
        final row = rows[i - h];
        return switch (row) {
          _SectionRow r => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(
              children: [
                if (r.icon != null) ...[
                  Icon(r.icon, size: 18, color: context.brand.icon),
                  const SizedBox(width: 8),
                ],
                Text(r.title, style: text.titleMedium),
              ],
            ),
          ),
          _TimeRow r => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(r.label, style: text.titleSmall),
          ),
          _SessionRow r => SessionTile(session: r.session),
          _EndedToggleRow r => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: SubtleButton(
              icon: expandedEnded ? Icons.expand_less : Icons.expand_more,
              label: expandedEnded
                  ? 'Hide ${r.count} ended'
                  : '${r.label} · ${r.count} ended',
              onPressed: onToggleEnded,
            ),
          ),
        };
      },
    );
  }
}

/// Sessions across all conference days, upcoming first, then what's on now,
/// then a collapsed "Already ended" group. Headers read "Tue 10 · 9:00 AM".
class SessionResults extends StatefulWidget {
  const SessionResults({
    super.key,
    required this.sessions,
    required this.now,
    this.summary,
    this.emptyTitle = 'No matching sessions',
    this.emptyMessage = 'Try a different search or clear the filters.',
  });

  final List<Session> sessions;
  final DateTime now;

  /// Small line above the list, e.g. "12 results across all days".
  final String? summary;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<SessionResults> createState() => _SessionResultsState();
}

class _SessionResultsState extends State<SessionResults> {
  bool _showEnded = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.sessions.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.search_off,
            title: w.emptyTitle,
            message: w.emptyMessage,
          ),
        ],
      );
    }
    final today = venueDay(w.now);
    String label(Session s) {
      final d = venueDay(s.start);
      final day = sameDay(d, today) ? 'Today' : fmtDayShort(d);
      return '$day · ${fmtTime(s.start)}';
    }

    return SessionRowsList(
      rows: upcomingFirstRows(
        sessions: w.sessions,
        now: w.now,
        expandedEnded: _showEnded,
        timeLabel: label,
        endedLabel: 'Already ended',
      ),
      header: w.summary == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                w.summary!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
      expandedEnded: _showEnded,
      onToggleEnded: () => setState(() => _showEnded = !_showEnded),
    );
  }
}
