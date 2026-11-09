import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../data/models.dart';
import '../data/venue_time.dart';
import '../screens/session_detail_screen.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import 'common.dart';

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, this.showDay = false});

  final Session session;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = session;
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final saved = app.isSaved(s.id);
    final loc = app.data.locate(s.roomId);
    final live = !app.now.isBefore(s.start) && app.now.isBefore(s.end);
    final speakers = s.speakers.map((p) => p.name).join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: BrandCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionDetailScreen(sessionId: s.id),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (live) ...[
                        const Pill('Live now', color: Brand.nativeOrange),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          [
                            if (showDay) fmtDayShort(venueDay(s.start)),
                            fmtRange(s.start, s.end),
                          ].join(' · '),
                          style: text.labelMedium?.copyWith(color: b.body),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s.title, style: text.titleSmall),
                  if (speakers.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      speakers,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        loc is OffsiteLocation
                            ? Icons.directions_walk
                            : Icons.place_outlined,
                        size: 16,
                        color: b.icon,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          loc.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(s.typeName, icon: kindIcon(s.type)),
                      if (s.track != null && s.track != s.typeName)
                        Pill(s.track!),
                      if (s.prerequisites.isNotEmpty)
                        const Pill('Prerequisites', icon: Icons.checklist),
                    ],
                  ),
                ],
              ),
            ),
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
      ),
    );
  }
}
