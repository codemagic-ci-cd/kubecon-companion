import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/venue_time.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/now_banner.dart';
import '../widgets/session_tile.dart';
import '../widgets/speaker_card.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  String _query = '';
  final _types = <String>{};
  final _tracks = <String>{};

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

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(),
        actions: const [SettingsAction()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
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
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final d in conferenceDays)
            _DayList(
              key: PageStorageKey('day-${d.day}'),
              day: d,
              isToday: sameDay(d, today),
              sessions: app
                  .sessionsOn(d)
                  .where((s) => _matches(app, s))
                  .toList(),
              filtered: _query.isNotEmpty || filterCount > 0,
            ),
        ],
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    super.key,
    required this.day,
    required this.isToday,
    required this.sessions,
    required this.filtered,
  });

  final DateTime day;
  final bool isToday;
  final List<Session> sessions;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    // Flatten into time headers + sessions for a single lazy list.
    final rows = <Object>[];
    DateTime? last;
    for (final s in sessions) {
      if (last == null || !s.start.isAtSameMomentAs(last)) {
        rows.add(s.start);
        last = s.start;
      }
      rows.add(s);
    }
    final header = isToday && !filtered ? 1 : 0;

    if (sessions.isEmpty) {
      return ListView(
        children: [
          if (header == 1) const NowBanner(),
          EmptyState(
            icon: Icons.search_off,
            title: filtered ? 'No matching sessions' : 'Nothing scheduled',
            message: filtered
                ? 'Try a different search or clear the filters.'
                : 'No sessions are listed for ${fmtDayLong(day, isDay: true)}.',
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length + header,
      itemBuilder: (context, i) {
        if (header == 1 && i == 0) return const NowBanner();
        final row = rows[i - header];
        if (row is DateTime) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              fmtTime(row),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        return SessionTile(session: row as Session);
      },
    );
  }
}
