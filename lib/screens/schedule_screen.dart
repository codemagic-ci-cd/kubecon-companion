import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/sponsors.dart';
import '../data/venue_time.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/share_app_sheet.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/now_banner.dart';
import '../widgets/session_results.dart';
import '../widgets/speaker_card.dart';
import '../widgets/sponsor_tile.dart';
import '../widgets/live_refresh.dart';
import 'expo_screen.dart';
import '../services/analytics.dart';

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
      initialIndex: app.openingDayIndex,
    );
    _restoreFilters(app);
  }

  static const _kFilterTypes = 'schedule_filter_types';
  static const _kFilterTracks = 'schedule_filter_tracks';

  /// Brings back the filters from the last visit, dropping any that no
  /// longer match a session (e.g. a track renamed in a data refresh).
  void _restoreFilters(AppState app) {
    final prefs = app.prefs;
    if (prefs == null) return;
    final types = {for (final s in app.data.sessions) s.type};
    final tracks = {for (final s in app.data.sessions) ?s.track};
    _types.addAll(
      (prefs.getStringList(_kFilterTypes) ?? const []).where(types.contains),
    );
    _tracks.addAll(
      (prefs.getStringList(_kFilterTracks) ?? const []).where(tracks.contains),
    );
  }

  void _saveFilters(AppState app) {
    app.prefs?.setStringList(_kFilterTypes, _types.toList());
    app.prefs?.setStringList(_kFilterTracks, _tracks.toList());
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

    final before = {..._types, ..._tracks};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void toggle(Set<String> set, String v) {
            setSheet(() => set.contains(v) ? set.remove(v) : set.add(v));
            setState(() {});
            _saveFilters(app);
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
                        _saveFilters(app);
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
    final after = {..._types, ..._tracks};
    if (after.isNotEmpty && !setEquals(before, after)) {
      track(Events.filter, {
        'types': (_types.toList()..sort()).join(', '),
        'tracks': (_tracks.toList()..sort()).join(', '),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final filterCount = _types.length + _tracks.length;
    final today = venueDay(app.now);
    // Search and filters both look across every conference day.
    final searching = _query.isNotEmpty || filterCount > 0;
    final results = searching
        ? app.data.sessions.where((s) => _matches(app, s)).toList()
        : const <Session>[];

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
                        onChanged: (v) {
                          final q = v.trim();
                          // Count a search once, never its text.
                          if (_query.isEmpty && q.isNotEmpty) {
                            track(Events.search);
                          }
                          setState(() => _query = q);
                        },
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search talks, speakers, companies',
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
      body: LiveRefresh(
        child: searching
            ? SessionResults(
                sessions: results,
                now: app.now,
                leading: _query.length < 2
                    ? null
                    : SponsorMatches.forQuery(app.sponsors, _query),
                summary:
                    '${results.length} ${results.length == 1 ? 'result' : 'results'} across all days',
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
                      nextDay:
                          conferenceDays.indexOf(d) < conferenceDays.length - 1
                          ? conferenceDays[conferenceDays.indexOf(d) + 1]
                          : null,
                      onNextDay: () => _tabs.animateTo(
                        (conferenceDays.indexOf(d) + 1).clamp(
                          0,
                          conferenceDays.length - 1,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// "Sponsors & booths" above session search results: the best 3 sponsor
/// matches and "See all N" into the Expo directory.
class SponsorMatches extends StatelessWidget {
  const SponsorMatches({super.key, required this.query, required this.matches});

  /// Null unless [query] names a sponsor or booth: topic words alone
  /// ("security") match many sponsor descriptions and would crowd out talks.
  static SponsorMatches? forQuery(List<Sponsor> sponsors, String query) {
    if (!hasStrongSponsorMatch(sponsors, query)) return null;
    return SponsorMatches(query: query, matches: rankSponsors(sponsors, query));
  }

  final String query;
  final List<Sponsor> matches;

  static const maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 18,
                color: context.brand.icon,
              ),
              const SizedBox(width: 8),
              Text('Sponsors & booths', style: text.titleMedium),
            ],
          ),
        ),
        for (final s in matches.take(maxShown))
          SponsorTile(sponsor: s, showTier: true),
        if (matches.length > maxShown)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SubtleButton(
              icon: Icons.storefront_outlined,
              label: 'See all ${matches.length}',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExpoScreen(initialQuery: query),
                ),
              ),
            ),
          ),
      ],
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
    this.nextDay,
    this.onNextDay,
  });

  final DateTime day;
  final bool isToday;
  final DateTime now;
  final List<Session> sessions;
  final bool filtered;

  /// The following conference day, for the "That's a wrap" card.
  final DateTime? nextDay;
  final VoidCallback? onNextDay;

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

    final List<SessionListRow> rows;
    if (w.isToday) {
      rows = upcomingFirstRows(
        sessions: w.sessions,
        now: w.now,
        expandedEnded: _showEnded,
        timeLabel: (s) => fmtTime(s.start),
        endedLabel: 'Earlier today',
      );
    } else {
      rows = <SessionListRow>[];
      addTimedRows(
        rows,
        [...w.sessions]..sort(bySessionStart),
        (s) => fmtTime(s.start),
      );
    }
    // Everything today has ended: say so and point to the next day instead
    // of showing only a collapsed "ended" row.
    final wrapped =
        w.isToday &&
        !w.filtered &&
        w.sessions.every((s) => !s.end.isAfter(w.now));
    final header = wrapped
        ? _WrapCard(nextDay: w.nextDay, onNextDay: w.onNextDay)
        : banner;
    return SessionRowsList(
      rows: rows,
      header: header,
      expandedEnded: _showEnded,
      onToggleEnded: () => setState(() => _showEnded = !_showEnded),
    );
  }
}

class _WrapCard extends StatelessWidget {
  const _WrapCard({this.nextDay, this.onNextDay});

  final DateTime? nextDay;
  final VoidCallback? onNextDay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: context.brand.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("That's a wrap for today", style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              nextDay == null
                  ? 'Thanks for joining KubeCon + CloudNativeCon North America 2026.'
                  : 'Nothing else is scheduled today. See what\'s on ${fmtDayLong(nextDay!, isDay: true)}.',
              style: text.bodyMedium,
            ),
            if (nextDay != null && onNextDay != null) ...[
              const SizedBox(height: 16),
              PrimaryButton(
                icon: Icons.arrow_forward,
                label: 'See ${fmtDayShort(nextDay!)}',
                onPressed: onNextDay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
