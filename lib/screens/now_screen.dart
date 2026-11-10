import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../data/venue_time.dart';
import '../services/notification_service.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/app_bar_title.dart';
import '../widgets/common.dart';
import '../widgets/now_banner.dart';
import '../widgets/live_refresh.dart';

/// Meals, breaks, receptions and other happenings, plus what's live now.
class NowScreen extends StatefulWidget {
  const NowScreen({super.key});

  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> {
  late int _day = AppScope.read(context).openingDayIndex;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final day = conferenceDays[_day];
    final now = app.now;
    final today = venueDay(now);
    final items = app.timelineFor(day);
    final facilities = app.facilitiesOn(day);
    final isToday = sameDay(day, today);
    final upcoming = isToday
        ? items.where((i) => i.end.isAfter(now)).toList()
        : items;
    final past = isToday
        ? items.where((i) => !i.end.isAfter(now)).toList()
        : const <TimelineItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle(),
        actions: const [SettingsAction()],
      ),
      body: LiveRefresh(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var i = 0; i < conferenceDays.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          sameDay(conferenceDays[i], today)
                              ? 'Today'
                              : fmtDayShort(conferenceDays[i]),
                        ),
                        labelStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(
                              color: i == _day
                                  ? Colors.white
                                  : context.brand.heading,
                            ),
                        selected: i == _day,
                        onSelected: (_) => setState(() => _day = i),
                      ),
                    ),
                ],
              ),
            ),
            if (!app.notificationsEnabled) const _NotifyPrompt(),
            if (isToday) const NowBanner(),
            SectionTitle(
              isToday ? 'Still to come today' : fmtDayLong(day, isDay: true),
            ),
            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  isToday
                      ? 'That is a wrap for today. See you tomorrow!'
                      : 'Nothing listed for this day yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final i in upcoming) _TimelineTile(item: i),
            if (facilities.isNotEmpty) ...[
              const SectionTitle('Good to know'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BrandCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      for (final f in facilities)
                        ListTile(
                          leading: Icon(_facilityIcon(f)),
                          title: Text(f.title),
                          subtitle: Text(
                            [
                              f.location ?? app.data.locate(f.roomId).label,
                              if (!f.title.toLowerCase().contains('room') ||
                                  f.kind == 'registration')
                                fmtRange(f.start, f.end),
                            ].join(' · '),
                          ),
                          onTap: () => openTimelineItem(
                            context,
                            TimelineItem.happening(f),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (past.isNotEmpty) ...[
              const SectionTitle('Earlier today'),
              for (final i in past) _TimelineTile(item: i, dimmed: true),
            ],
          ],
        ),
      ),
    );
  }

  IconData _facilityIcon(Happening h) {
    final t = h.title.toLowerCase();
    if (t.contains('first aid')) return Icons.medical_services_outlined;
    if (t.contains('prayer') || t.contains('quiet')) {
      return Icons.self_improvement;
    }
    if (t.contains('nursing')) return Icons.child_friendly_outlined;
    if (t.contains('child')) return Icons.child_care;
    if (t.contains('coat')) return Icons.checkroom;
    if (t.contains('safety') || t.contains('lost')) {
      return Icons.shield_outlined;
    }
    if (h.kind == 'registration') return Icons.badge_outlined;
    return Icons.info_outline;
  }
}

class _NotifyPrompt extends StatelessWidget {
  const _NotifyPrompt();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.permission == NotificationPermission.unsupported) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: Brand.blueGradient,
          borderRadius: BorderRadius.circular(Brand.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Never miss lunch again',
              style: text.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              'Get a heads-up 10 minutes before meals, coffee breaks, receptions and your saved sessions.',
              style: text.bodyMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Brand.noBugBlue,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final p = await app.setNotificationsEnabled(true);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      p == NotificationPermission.granted
                          ? 'Reminders are on.'
                          : 'Notifications are blocked. Allow them in your browser or system settings.',
                    ),
                  ),
                );
              },
              child: const Text('Turn on reminders'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.item, this.dimmed = false});
  final TimelineItem item;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final live = item.isLive(app.now);
    final loc = app.data.locate(item.roomId, fallbackText: item.locationText);
    final where = loc is UnknownLocation
        ? (item.locationText ?? loc.label)
        : loc.label;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: BrandCard(
          onTap: () => openTimelineItem(context, item),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kindColor(item.kind),
                  borderRadius: BorderRadius.circular(Brand.radiusMd),
                ),
                child: Icon(kindIcon(item.kind), color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (live) ...[
                          const Pill('Now', color: Brand.nativeOrange),
                          const SizedBox(width: 8),
                        ] else if (item.mine) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Brand.swwYellow,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            fmtRange(item.start, item.end),
                            style: text.labelMedium?.copyWith(
                              color: context.brand.body,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.title, style: text.titleSmall),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          loc is OffsiteLocation
                              ? Icons.directions_walk
                              : Icons.place_outlined,
                          size: 14,
                          color: context.brand.icon,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            where,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
