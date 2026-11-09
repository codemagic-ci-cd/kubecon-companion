import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/venue_time.dart';
import '../services/notification_service.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import '../widgets/speaker_card.dart';
import 'directions_screen.dart';

class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Schedule data right away; description, prerequisites and speaker bios
    // are merged in once details.json has loaded.
    final s = app.detailedSession(sessionId);
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
    final reminded = app.isReminderOn(s.id);
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
              RoomLocation l => l.levelLabel,
              OffsiteLocation o => o.venue.address ?? 'Off-site',
              UnknownLocation _ => 'Not on our venue map yet',
            },
            actionLabel: loc is OffsiteLocation ? 'Walk there' : 'Directions',
            actionIcon: loc is OffsiteLocation
                ? Icons.directions_walk
                : Icons.directions,
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
                      : saved
                      ? 'Reminder off'
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
                                    ? (saved
                                          ? 'Reminder off. It stays in Saved.'
                                          : 'Reminder removed.')
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
          ] else if (app.detailsStatus == DetailsStatus.loading)
            const _DetailsLoading()
          else if (app.detailsStatus == DetailsStatus.failed)
            _DetailsFailed(
              onRetry: app.loadDetails,
              withPrerequisites: s.hasPrerequisites,
            ),
          if (s.speakers.isNotEmpty) ...[
            SectionTitle(
              s.speakers.length == 1 ? 'Speaker' : 'Speakers',
              padding: const EdgeInsets.only(top: 24, bottom: 8),
            ),
            for (final p in s.speakers) SpeakerCard(speaker: p),
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
    this.actionLabel,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// When set (with [onTap]), shows a compact primary button instead of a chevron.
  final String? actionLabel;
  final IconData? actionIcon;

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
            if (onTap != null && actionLabel != null) ...[
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.radiusMd),
                  ),
                ),
                icon: Icon(actionIcon ?? Icons.directions, size: 18),
                label: Text(actionLabel!),
              ),
            ] else if (onTap != null)
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

/// Placeholder while details.json (description, bios) is still loading.
class _DetailsLoading extends StatelessWidget {
  const _DetailsLoading();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    Widget bar(double widthFactor) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 12,
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: b.subtle,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
        ),
      ),
    );
    return Semantics(
      key: const ValueKey('details-loading'),
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Loading details…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            bar(1),
            bar(0.92),
            bar(0.6),
          ],
        ),
      ),
    );
  }
}

/// details.json could not be loaded: everything else on the screen still
/// works, so say so quietly and offer a retry.
class _DetailsFailed extends StatelessWidget {
  const _DetailsFailed({required this.onRetry, this.withPrerequisites = false});
  final Future<void> Function() onRetry;
  final bool withPrerequisites;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 20, color: context.brand.icon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              withPrerequisites
                  ? 'Could not load the description and prerequisites. '
                        'Check your connection.'
                  : 'Could not load the description. Check your connection.',
              style: text.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
