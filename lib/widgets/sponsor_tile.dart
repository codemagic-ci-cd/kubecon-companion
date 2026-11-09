import 'package:flutter/material.dart';

import '../data/sponsors.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import 'common.dart';

/// A sponsor row: name, booth and hall, solution categories. Tap for details.
class SponsorTile extends StatelessWidget {
  const SponsorTile({super.key, required this.sponsor, this.showTier = false});

  final Sponsor sponsor;

  /// Adds the tier to the booth line (lists not grouped by tier).
  final bool showTier;

  @override
  Widget build(BuildContext context) {
    final s = sponsor;
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final where = [
      s.boothLabel ?? 'No booth listed',
      if (showTier) s.tier,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: BrandCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        onTap: () => showSponsorSheet(context, s),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        s.booth == null
                            ? Icons.storefront_outlined
                            : Icons.place_outlined,
                        size: 16,
                        color: b.icon,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          where,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: s.booth == null ? null : b.heading,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (s.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      s.tags.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: b.icon),
          ],
        ),
      ),
    );
  }
}

Future<void> showSponsorSheet(BuildContext context, Sponsor sponsor) {
  final app = AppScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AppScope(
      state: app,
      child: SponsorSheet(sponsor: sponsor),
    ),
  );
}

/// Sponsor details: booth, description, website and "Show on map".
class SponsorSheet extends StatelessWidget {
  const SponsorSheet({super.key, required this.sponsor});
  final Sponsor sponsor;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = sponsor;
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final onMap = s.roomId != null && app.data.venue.room(s.roomId) != null;
    final website = s.website;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.name, style: text.headlineSmall),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Pill('${s.tier} sponsor'),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined, size: 20, color: b.icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.boothLabel ?? 'No booth listed on the floor plan',
                      style: text.titleSmall,
                    ),
                  ),
                ],
              ),
              if (s.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(s.description, style: text.bodyMedium),
              ],
              if (s.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final t in s.tags) Pill(t)],
                ),
              ],
              if (onMap) ...[
                const SizedBox(height: 24),
                PrimaryButton(
                  icon: Icons.map_outlined,
                  label: 'Show on map',
                  onPressed: () {
                    Navigator.pop(context);
                    app.showOnMap(s.roomId!);
                  },
                ),
              ],
              if (website != null) ...[
                SizedBox(height: onMap ? 12 : 24),
                SubtleButton(
                  icon: Icons.open_in_new,
                  label: 'Website',
                  onPressed: () => openLink(context, website),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
