import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/venue_time.dart';
import '../screens/directions_screen.dart';
import '../screens/session_detail_screen.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import 'common.dart';

/// Opens the right detail view for a timeline row.
void openTimelineItem(BuildContext context, TimelineItem item) {
  if (item.session != null) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionDetailScreen(sessionId: item.session!.id),
      ),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _HappeningSheet(item: item),
  );
}

class _HappeningSheet extends StatelessWidget {
  const _HappeningSheet({required this.item});
  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final h = item.happening!;
    final loc = app.data.locate(h.roomId, fallbackText: h.location);
    final canNavigate = loc is! UnknownLocation;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Pill(happeningLabel(h.kind), icon: kindIcon(h.kind)),
            const SizedBox(height: 12),
            Text(h.title, style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${fmtDayLong(h.start)} · ${fmtRange(h.start, h.end)}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              loc is UnknownLocation ? (h.location ?? loc.label) : loc.label,
              style: text.bodyMedium?.copyWith(color: context.brand.heading),
            ),
            if (h.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(h.description, style: text.bodyMedium),
            ],
            const SizedBox(height: 24),
            if (canNavigate)
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  icon: Icons.directions,
                  label: 'Get directions',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DirectionsScreen(roomId: h.roomId!),
                      ),
                    );
                  },
                ),
              ),
            if (h.url != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SubtleButton(
                  icon: Icons.open_in_new,
                  label: 'More info',
                  onPressed: () => openLink(context, h.url!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String happeningLabel(String kind) => switch (kind) {
  'meal' => 'Meal',
  'break' => 'Break',
  'keynote' => 'Keynotes',
  'social' => 'Social',
  'party' => 'Party',
  'expo' => 'Expo',
  'registration' => 'Registration',
  _ => 'Good to know',
};

/// Compact "Happening now / next" card, shown on conference days.
class NowBanner extends StatelessWidget {
  const NowBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = app.now;
    final today = venueDay(now);
    if (!conferenceDays.any((d) => sameDay(d, today)) &&
        app.lastFired == null) {
      return const SizedBox.shrink();
    }
    final items = app.timelineFor(today);
    // Meals, breaks and parties beat all-day things like the expo hall.
    int rank(TimelineItem i) => switch (i.kind) {
      'meal' || 'break' || 'keynote' => 0,
      'social' || 'party' => 1,
      _ => i.mine ? 1 : 2,
    };
    final live = items.where((i) => i.isLive(now)).toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    if (live.length > 2) live.removeRange(2, live.length);
    final next = items.where((i) => i.start.isAfter(now)).firstOrNull;
    final fired = app.lastFired;
    if (live.isEmpty && next == null && fired == null) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;

    Widget row(String label, TimelineItem item, String when, Color color) =>
        InkWell(
          borderRadius: BorderRadius.circular(Brand.radiusMd),
          onTap: () => openTimelineItem(context, item),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(Brand.radiusMd),
                  ),
                  child: Icon(
                    kindIcon(item.kind),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$label · $when',
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.title,
                        style: text.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.brand.icon),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: BrandCard(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Column(
          children: [
            if (fired != null)
              Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: Brand.swwYellow,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${fired.title} · ${fmtRelative(fired.startsAt, now)}',
                      style: text.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: app.dismissFired,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            for (final i in live)
              row(
                'Happening now',
                i,
                'until ${fmtTime(i.end)}',
                Brand.nativeOrange,
              ),
            if (next != null)
              row(
                'Up next',
                next,
                '${fmtTime(next.start)}, ${fmtRelative(next.start, now)}',
                Brand.neverBlue,
              ),
          ],
        ),
      ),
    );
  }
}
