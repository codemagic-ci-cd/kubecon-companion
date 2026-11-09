import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/venue_time.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/share_app_sheet.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/now_banner.dart';
import '../widgets/session_tile.dart';
import '../widgets/speaker_card.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    this.initialTypes = const {},
    this.initialTracks = const {},
  });

  /// Filters applied on open, e.g. when a type or track pill on a session
  /// page is tapped.
  final Set<String> initialTypes;
  final Set<String> initialTracks;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  String _query = '';
  late final _types = <String>{...widget.initialTypes};
  late final _tracks = <String>{...widget.initialTracks};

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _tabs = TabController(
      length: conferenceDays.length,
      vsync: this,
      initialIndex: defaultDayIndex(app.now),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppState app, Session s) {
    if (_types.isNotEmpty && !_types.contains(s.type)) return false;
    if (_tracks.isNotEmpty && !_tracks.contains(s.track)) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final hq = q.replaceFirst(RegExp(r'^@'), '');
    if (s.title.toLowerCase().contains(q)) return true;
    if ((s.track ?? '').toLowerCase().contains(q)) return true;
    if (s.speakers.any(
      (p) =>
          p.name.toLowerCase().contains(q) ||
          (p.company ?? '').toLowerCase().contains(q) ||
          (hq.isNotEmpty && speakerHandles(p).any((h) => h.contains(hq))),
    )) {
      return true;
    }
    return app.data.locate(s.roomId).label.toLowerCase().contains(q);
  }

  Future<void> _openFilters(AppState app) async {
    final typeCounts = <String, int>{};
    final trackCounts = <String, int>{};
    for (final s in app.data.sessions) {
      typeCounts[s.type] = (typeCounts[s.type] ?? 0) + 1;
      if (s.track != null) {
        trackCounts[s.track!] = (trackCounts[s.track!] ?? 0) + 1;
      }
    }
    final types = typeCounts.keys.toList()
      ..sort((a, b) => typeCounts[b]!.compareTo(typeCounts[a]!));
    final tracks = trackCounts.keys.toList()..sort();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void toggle(Set<String> set, String v) {
            setSheet(() => set.contains(v) ? set.remove(v) : set.add(v));
            setState(() {});
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter sessions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setSheet(() {
                          _types.clear();
                          _tracks.clear();
                        });
                        setState(() {});
                      },
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
                const SectionTitle(
                  'Type',
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in types)
                      FilterChip(
                        label: Text('${typeLabel(t)} (${typeCounts[t]})'),
                        selected: _types.contains(t),
                        onSelected: (_) => toggle(_types, t),
                      ),
                  ],
                ),
                const SectionTitle(
                  'Track',
                  padding: EdgeInsets.only(top: 24, bottom: 8),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tracks)
                      FilterChip(
                        label: Text(t),
                        selected: _tracks.contains(t),
                        onSelected: (_) => toggle(_tracks, t),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Show sessions',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final filterCount = _types.length + _tracks.length;
    final today = venueDay(app.now);
    // Search and filters both look across every conference day.
    final searching = _query.isNotEmpty || filterCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(),
        actions: const [ShareAppAction(), SettingsAction()],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(searching ? 64 : 112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v.trim()),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search talks, speakers, rooms',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() {
                                    _search.clear();
                                    _query = '';
                                  }),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: filterCount > 0,
                      label: Text('$filterCount'),
                      backgroundColor: Brand.swwYellow,
                      textColor: Brand.darkPage,
                      child: IconButton.filledTonal(
                        tooltip: 'Filter by type and track',
                        style: IconButton.styleFrom(
                          backgroundColor: context.brand.subtle,
                          foregroundColor: context.brand.heading,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.radiusMd),
                          ),
                        ),
                        onPressed: () => _openFilters(app),
                        icon: const Icon(Icons.tune),
                      ),
                    ),
                  ],
                ),
              ),
              if (!searching)
                TabBar(
                  controller: _tabs,
                  tabs: [
                    for (final d in conferenceDays)
                      Tab(text: sameDay(d, today) ? 'Today' : fmtDayShort(d)),
                  ],
                ),
            ],
          ),
        ),
      ),
      body: searching
          ? _SearchResults(
              sessions: app.data.sessions
                  .where((s) => _matches(app, s))
                  .toList(),
              now: app.now,
            )
          : TabBarView(
              controller: _tabs,
              children: [
                for (final d in conferenceDays)
                  _DayList(
                    key: PageStorageKey('day-${d.day}'),
                    day: d,
                    isToday: sameDay(d, today),
                    now: app.now,
                    sessions: app
                        .sessionsOn(d)
                        .where((s) => _matches(app, s))
                        .toList(),
                    filtered: filterCount > 0,
                  ),
              ],
            ),
    );
  }
}

/// Rows for a lazy list: section titles, time headers and sessions.
sealed class _Row {}

class _SectionRow extends _Row {
  _SectionRow(this.title, {this.icon});
  final String title;
  final IconData? icon;
}

class _TimeRow extends _Row {
  _TimeRow(this.label);
  final String label;
}

class _SessionRow extends _Row {
  _SessionRow(this.session);
  final Session session;
}

class _EndedToggleRow extends _Row {
  _EndedToggleRow(this.count, this.label);
  final int count;
  final String label;
}

/// Adds sessions with a time header whenever the label changes.
void _addTimed(
  List<_Row> rows,
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

int _byStart(Session a, Session b) {
  final c = a.start.compareTo(b.start);
  return c != 0 ? c : a.title.compareTo(b.title);
}

/// Upcoming first, then what's on now, then (collapsed) what has ended.
List<_Row> _upcomingFirst({
  required List<Session> sessions,
  required DateTime now,
  required bool expandedEnded,
  required String Function(Session) timeLabel,
  required String endedLabel,
}) {
  final upcoming = sessions.where((s) => !s.start.isBefore(now)).toList()
    ..sort(_byStart);
  final live =
      sessions
          .where((s) => s.start.isBefore(now) && s.end.isAfter(now))
          .toList()
        ..sort((a, b) => a.end.compareTo(b.end));
  final ended = sessions.where((s) => !s.end.isAfter(now)).toList()
    ..sort(_byStart);

  final rows = <_Row>[];
  if (upcoming.isNotEmpty) {
    rows.add(_SectionRow('Coming up', icon: Icons.upcoming_outlined));
    _addTimed(rows, upcoming, timeLabel);
  }
  if (live.isNotEmpty) {
    rows.add(_SectionRow('Happening now', icon: Icons.sensors));
    for (final s in live) {
      rows.add(_SessionRow(s));
    }
  }
  if (ended.isNotEmpty) {
    rows.add(_EndedToggleRow(ended.length, endedLabel));
    if (expandedEnded) _addTimed(rows, ended, timeLabel);
  }
  return rows;
}

class _RowsList extends StatelessWidget {
  const _RowsList({
    required this.rows,
    this.header,
    this.expandedEnded = false,
    this.onToggleEnded,
  });

  final List<_Row> rows;
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

class _DayList extends StatefulWidget {
  const _DayList({
    super.key,
    required this.day,
    required this.isToday,
    required this.now,
    required this.sessions,
    required this.filtered,
  });

  final DateTime day;
  final bool isToday;
  final DateTime now;
  final List<Session> sessions;
  final bool filtered;

  @override
  State<_DayList> createState() => _DayListState();
}

class _DayListState extends State<_DayList> {
  bool _showEnded = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final banner = w.isToday && !w.filtered ? const NowBanner() : null;

    if (w.sessions.isEmpty) {
      return ListView(
        children: [
          ?banner,
          EmptyState(
            icon: Icons.search_off,
            title: w.filtered ? 'No matching sessions' : 'Nothing scheduled',
            message: w.filtered
                ? 'Try a different search or clear the filters.'
                : 'No sessions are listed for ${fmtDayLong(w.day, isDay: true)}.',
          ),
        ],
      );
    }

    final List<_Row> rows;
    if (w.isToday) {
      rows = _upcomingFirst(
        sessions: w.sessions,
        now: w.now,
        expandedEnded: _showEnded,
        timeLabel: (s) => fmtTime(s.start),
        endedLabel: 'Earlier today',
      );
    } else {
      rows = <_Row>[];
      _addTimed(rows, [...w.sessions]..sort(_byStart), (s) => fmtTime(s.start));
    }
    return _RowsList(
      rows: rows,
      header: banner,
      expandedEnded: _showEnded,
      onToggleEnded: () => setState(() => _showEnded = !_showEnded),
    );
  }
}

/// Search results across all conference days, upcoming first.
class _SearchResults extends StatefulWidget {
  const _SearchResults({required this.sessions, required this.now});

  final List<Session> sessions;
  final DateTime now;

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  bool _showEnded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.search_off,
            title: 'No matching sessions',
            message: 'Try a different search or clear the filters.',
          ),
        ],
      );
    }
    final today = venueDay(widget.now);
    String label(Session s) {
      final d = venueDay(s.start);
      final day = sameDay(d, today) ? 'Today' : fmtDayShort(d);
      return '$day · ${fmtTime(s.start)}';
    }

    return _RowsList(
      rows: _upcomingFirst(
        sessions: widget.sessions,
        now: widget.now,
        expandedEnded: _showEnded,
        timeLabel: label,
        endedLabel: 'Already ended',
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          '${widget.sessions.length} results across all days',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      expandedEnded: _showEnded,
      onToggleEnded: () => setState(() => _showEnded = !_showEnded),
    );
  }
}
