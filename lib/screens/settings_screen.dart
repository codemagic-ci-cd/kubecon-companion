import 'package:flutter/material.dart';

import '../data/venue_time.dart';
import '../services/notification_service.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final info = app.data.info;
    final schedule = app.data.schedule;
    final reminders = app.notificationsEnabled
        ? app.upcomingReminders
        : const [];
    final blocked =
        app.notificationsEnabled &&
        app.permission != NotificationPermission.granted;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings and about')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          BrandCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Reminders'),
                  subtitle: Text(
                    blocked
                        ? 'Notifications are blocked. Allow them in your browser or system settings.'
                        : '10 minutes before meals, breaks, receptions and saved sessions.',
                  ),
                  value: app.notificationsEnabled,
                  onChanged: (on) => app.setNotificationsEnabled(on),
                ),
                if (app.notificationsEnabled)
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text('${reminders.length} reminders scheduled'),
                    subtitle: Text(
                      reminders.isEmpty
                          ? 'Nothing coming up.'
                          : 'Next: ${reminders.first.title}, ${fmtDayShort(venueDay(reminders.first.fireAt))} ${fmtTime(reminders.first.fireAt)}',
                    ),
                    trailing: TextButton(
                      onPressed: () => app.notifications.showNow(
                        'KubeCon Companion',
                        'Reminders are working. See you at the next coffee break!',
                      ),
                      child: const Text('Test'),
                    ),
                  ),
                if (app.notifications.platformNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      app.notifications.platformNote,
                      style: text.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SectionTitle(
            'Appearance',
            padding: EdgeInsets.only(top: 24, bottom: 8),
          ),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setThemeMode(s.first),
          ),
          if (info.emergency != null ||
              info.codeOfConduct != null ||
              info.wifi != null) ...[
            const SectionTitle(
              'Safety and info',
              padding: EdgeInsets.only(top: 24, bottom: 8),
            ),
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.wifi != null) ...[
                    Text('Wi-Fi', style: text.titleSmall),
                    SelectableText(info.wifi!, style: text.bodyMedium),
                    const SizedBox(height: 12),
                  ],
                  if (info.emergency != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.emergency_outlined, color: Brand.red),
                        const SizedBox(width: 8),
                        Text('Emergency', style: text.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(info.emergency!, style: text.bodyMedium),
                  ],
                  if (info.codeOfConduct != null) ...[
                    const SizedBox(height: 12),
                    SubtleButton(
                      icon: Icons.gavel_outlined,
                      label: 'Code of conduct',
                      onPressed: () => openLink(context, info.codeOfConduct!),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (info.links.isNotEmpty) ...[
            const SectionTitle(
              'Links',
              padding: EdgeInsets.only(top: 24, bottom: 8),
            ),
            BrandCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final l in info.links)
                    ListTile(
                      dense: true,
                      title: Text(l.title),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => openLink(context, l.url),
                    ),
                ],
              ),
            ),
          ],
          const SectionTitle(
            'About',
            padding: EdgeInsets.only(top: 24, bottom: 8),
          ),
          const AboutCard(),
          const SizedBox(height: 16),
          Text(
            [
              'Schedule: ${schedule.sessions.length} sessions'
                  '${schedule.isSample ? ' (sample data)' : ''}'
                  '${schedule.fetchedAt != null ? ', updated ${fmtDayShort(venueDay(schedule.fetchedAt!))} ${fmtTime(schedule.fetchedAt!)}' : ''}.',
              'Times are shown in Salt Lake City time (MST).',
              if (app.data.venue.isApproximate) 'The venue map is a schematic reconstruction of the official map and is not to scale.',
              'This is an unofficial companion app, not affiliated with the event organisers.',
            ].join(' '),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BrandCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CodemagicLogo(height: 28),
          const SizedBox(height: 16),
          Text('Built & shipped with Codemagic', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            'One Flutter codebase, three targets: this app is built, tested and released to the web, Android and iOS by Codemagic CI/CD on every push.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Visit codemagic.io',
              icon: Icons.open_in_new,
              onPressed: () => openLink(context, 'https://codemagic.io'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.code),
              label: const Text('Source code on GitHub'),
              onPressed: () => openLink(
                context,
                'https://github.com/codemagic-ci-cd/kubecon-companion',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => openLink(
                context,
                'https://kubecon.codemagic.app/privacy/index.html',
              ),
              child: const Text('Privacy policy'),
            ),
          ),
        ],
      ),
    );
  }
}
