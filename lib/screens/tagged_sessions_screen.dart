import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import '../widgets/session_results.dart';

/// Every session sharing one tag (type, track or level), across all days,
/// upcoming first. Opened from the pills on a session page.
class TaggedSessionsScreen extends StatelessWidget {
  const TaggedSessionsScreen({
    super.key,
    required this.title,
    required this.filter,
    this.subtitle,
  });

  /// The tag, e.g. "Platform Engineering Day".
  final String title;

  /// Defaults to the session count, e.g. "29 sessions".
  final String? subtitle;
  final bool Function(Session) filter;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sessions = app.data.sessions.where(filter).toList();
    final n = sessions.length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              subtitle ?? '$n ${n == 1 ? 'session' : 'sessions'}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.brand.body),
            ),
          ],
        ),
      ),
      body: SessionResults(
        sessions: sessions,
        now: app.now,
        emptyTitle: 'No sessions',
        emptyMessage: 'Nothing on the schedule has this tag right now.',
      ),
    );
  }
}
