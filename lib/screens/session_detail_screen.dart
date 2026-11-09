import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../data/venue_time.dart';
import '../services/notification_service.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import 'directions_screen.dart';

class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.data.session(sessionId);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.event_busy,
          title: 'Session not found',
          message: 'It may have been removed from the schedule.',
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final loc = app.data.locate(s.roomId);
    final saved = app.isSaved(s.id);
    final reminded = app.isReminded(s.id);
    final started = !app.now.isBefore(s.start);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: saved ? 'Remove from saved' : 'Save',
            onPressed: () => app.toggleSaved(s.id),
            icon: Icon(
              saved ? Icons.star_rounded : Icons.star_outline_rounded,
              color: saved ? Brand.swwYellow : b.icon,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(s.typeName, icon: kindIcon(s.type)),
              if (s.track != null && s.track != s.typeName) Pill(s.track!),
              if (s.levelName != null)
                Pill(s.levelName!, icon: Icons.signal_cellular_alt),
            ],
          ),
          const SizedBox(height: 12),
          Text(s.title, style: text.headlineSmall),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.schedule,
            title: fmtRange(s.start, s.end),
            subtitle:
                '${fmtDayLong(s.start)} · ${fmtDuration(s.end.difference(s.start))}',
          ),
          _InfoRow(
            icon: loc is OffsiteLocation
                ? Icons.directions_walk
                : Icons.place_outlined,
            title: loc.label,
            subtitle: switch (loc) {
              RoomLocation l => '${l.levelLabel} · tap for directions',
              OffsiteLocation o =>
                '${o.venue.address ?? 'Off-site'} · tap for walking directions',
              UnknownLocation _ => 'Not on our venue map yet',
            },
            onTap: loc is UnknownLocation
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DirectionsScreen(roomId: s.roomId),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  icon: saved ? Icons.star_rounded : Icons.star_outline_rounded,
                  label: saved ? 'Saved' : 'Save',
                  onPressed: () => app.toggleSaved(s.id),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SubtleButton(
                  icon: reminded
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  label: started
                      ? 'Already started'
                      : reminded
                      ? 'Reminder on'
                      : 'Add reminder',
                  onPressed: started
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final on = await app.toggleReminder(s.id);
                          final perm = app.permission;
                          final blocked =
                              perm == NotificationPermission.denied ||
                              perm == NotificationPermission.unsupported;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                !on
                                    ? 'Reminder removed.'
                                    : blocked
                                    ? 'Saved. Notifications are off for this browser, so look for it in the Now tab. ${app.notifications.platformNote}'
                                    : 'We will remind you 10 minutes before it starts.',
                              ),
                            ),
                          );
                        },
                ),
              ),
            ],
          ),
          if (s.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 24),
            _Prerequisites(items: s.prerequisites),
          ],
          if (s.description.isNotEmpty) ...[
            const SectionTitle(
              'About this session',
              padding: EdgeInsets.only(top: 24, bottom: 8),
            ),
            SelectableText(s.description, style: text.bodyMedium),
          ],
          if (s.speakers.isNotEmpty) ...[
            SectionTitle(
              s.speakers.length == 1 ? 'Speaker' : 'Speakers',
              padding: const EdgeInsets.only(top: 24, bottom: 8),
            ),
            for (final p in s.speakers) _SpeakerCard(speaker: p),
          ],
          if (s.url != null) ...[
            const SizedBox(height: 16),
            SubtleButton(
              icon: Icons.open_in_new,
              label: 'View on the official schedule',
              onPressed: () => openLink(context, s.url!),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(Brand.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.brand.subtle,
                borderRadius: BorderRadius.circular(Brand.radiusMd),
              ),
              child: Icon(icon, color: context.brand.icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.labelLarge?.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, color: context.brand.icon),
          ],
        ),
      ),
    );
  }
}

class _Prerequisites extends StatelessWidget {
  const _Prerequisites({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radiusCard),
        gradient: Brand.magentaGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Before you go',
                style: text.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p,
                      style: text.bodyMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SpeakerCard extends StatefulWidget {
  const _SpeakerCard({required this.speaker});
  final Speaker speaker;

  @override
  State<_SpeakerCard> createState() => _SpeakerCardState();
}

class _SpeakerCardState extends State<_SpeakerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.speaker;
    final text = Theme.of(context).textTheme;
    final initials = p.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final bio = p.bio;
    final long = bio != null && bio.length > 220;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BrandCard(
        onTap: long ? () => setState(() => _expanded = !_expanded) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: Brand.blueGradient,
                  ),
                  child: Text(
                    initials,
                    style: text.labelLarge?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: text.titleSmall),
                      if (p.role.isNotEmpty)
                        Text(p.role, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (bio != null) ...[
              const SizedBox(height: 12),
              Text(
                bio,
                style: text.bodyMedium,
                maxLines: _expanded ? null : 4,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
              if (long)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _expanded ? 'Show less' : 'Read more',
                    style: text.labelLarge?.copyWith(
                      color: context.brand.isDark
                          ? Brand.dashAqua
                          : Brand.neverBlue,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
