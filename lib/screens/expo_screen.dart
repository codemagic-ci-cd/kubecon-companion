import 'package:flutter/material.dart';

import '../data/sponsors.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/sponsor_tile.dart';
import '../widgets/live_refresh.dart';

/// Sponsor and booth directory for the Solutions Showcase: search, tier
/// filter, list grouped by tier, opening hours on top.
class ExpoScreen extends StatefulWidget {
  const ExpoScreen({super.key, this.initialQuery = ''});

  /// Pre-fills the search, e.g. from "See all" in schedule search.
  final String initialQuery;

  @override
  State<ExpoScreen> createState() => _ExpoScreenState();
}

sealed class _Row {}

class _TierRow extends _Row {
  _TierRow(this.tier, this.count);
  final String tier;
  final int count;
}

class _SponsorRow extends _Row {
  _SponsorRow(this.sponsor);
  final Sponsor sponsor;
}

class _ExpoScreenState extends State<ExpoScreen> {
  late final _search = TextEditingController(text: widget.initialQuery.trim());
  late String _query = widget.initialQuery.trim();
  String? _tier;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() => setState(() {
    _search.clear();
    _query = '';
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.sponsors;
    final matching = filterSponsors(all, _query);
    final shown = _tier == null
        ? matching
        : matching.where((s) => s.tier == _tier).toList();
    final counts = <String, int>{};
    for (final s in matching) {
      counts[s.tier] = (counts[s.tier] ?? 0) + 1;
    }
    final tiers = {for (final s in all) s.tier}.toList()
      ..sort((a, b) => tierRank(a).compareTo(tierRank(b)));
    final filtering = _query.isNotEmpty || _tier != null;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(),
        actions: const [SettingsAction()],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(tiers.isEmpty ? 64 : 112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search sponsors, booths, topics',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: _clearSearch,
                          ),
                  ),
                ),
              ),
              if (tiers.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      _TierChip(
                        label: 'All ${matching.length}',
                        selected: _tier == null,
                        onSelected: () => setState(() => _tier = null),
                      ),
                      for (final t in tiers)
                        _TierChip(
                          label: '$t ${counts[t] ?? 0}',
                          selected: _tier == t,
                          onSelected: () =>
                              setState(() => _tier = _tier == t ? null : t),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      body: LiveRefresh(
        child: switch (app.sponsorsStatus) {
          DetailsStatus.loading when all.isEmpty => const PullableFill(
            child: EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Loading sponsors…',
              message: 'The booth directory is on its way.',
            ),
          ),
          DetailsStatus.failed when all.isEmpty => PullableFill(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load sponsors',
              message: 'Check your connection and try again.',
              action: PrimaryButton(
                icon: Icons.refresh,
                label: 'Try again',
                onPressed: () => app.loadSponsors(),
              ),
            ),
          ),
          _ when all.isEmpty => const PullableFill(
            child: EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No sponsors yet',
              message: 'The sponsor directory has not been published.',
            ),
          ),
          _ => _list(context, app, shown, filtering),
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    AppState app,
    List<Sponsor> shown,
    bool filtering,
  ) {
    final text = Theme.of(context).textTheme;
    final hours = filtering ? null : expoHours(app.data.happenings, app.now);
    final rows = <_Row>[];
    String? last;
    for (final s in shown) {
      if (s.tier != last) {
        rows.add(_TierRow(s.tier, shown.where((x) => x.tier == s.tier).length));
        last = s.tier;
      }
      rows.add(_SponsorRow(s));
    }
    final header = <Widget>[
      if (hours != null) _HoursCard(hours: hours),
      if (filtering)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            '${shown.length} ${shown.length == 1 ? 'sponsor' : 'sponsors'}',
            style: text.bodySmall,
          ),
        ),
      if (shown.isEmpty)
        EmptyState(
          icon: Icons.search_off,
          title: 'No matching sponsors',
          message: 'Try a company name, booth number or topic.',
          action: SubtleButton(
            icon: Icons.close,
            label: 'Clear search and filters',
            onPressed: () => setState(() {
              _search.clear();
              _query = '';
              _tier = null;
            }),
          ),
        ),
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: header.length + rows.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        return switch (rows[i - header.length]) {
          _TierRow r => Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('${r.tier} · ${r.count}', style: text.titleMedium),
          ),
          _SponsorRow r => SponsorTile(sponsor: r.sponsor),
        };
      },
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
    ),
  );
}

class _HoursCard extends StatelessWidget {
  const _HoursCard({required this.hours});
  final ExpoHours hours;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: BrandCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.storefront_outlined,
              color: hours.isOpen ? Brand.continuousBlue : context.brand.icon,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hours.title, style: text.titleSmall),
                  if (hours.detail != null) ...[
                    const SizedBox(height: 4),
                    Text(hours.detail!, style: text.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
