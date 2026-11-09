import 'package:flutter/material.dart';

import '../data/ics.dart';
import '../data/models.dart';
import '../services/calendar_export.dart';
import '../state/app_state.dart';

/// Builds an .ics for [sessions] and hands it to the platform. One session
/// gets `kubecon-<title-slug>.ics`, several `kubecon-agenda.ics`. Shows a
/// snackbar when that fails. [anchor] positions the iPad share popover.
Future<void> exportToCalendar(
  BuildContext anchor,
  AppState app,
  List<Session> sessions,
) async {
  if (sessions.isEmpty) return;
  final messenger = ScaffoldMessenger.of(anchor);
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  final content = buildIcs([
    for (final s in sessions) icsEventFor(s, app.data.locate(s.roomId)),
  ], stamp: DateTime.now().toUtc());
  final filename = sessions.length == 1
      ? 'kubecon-${icsSlug(sessions.single.title)}.ics'
      : 'kubecon-agenda.ics';
  try {
    await deliverIcs(filename: filename, content: content, origin: origin);
  } catch (e) {
    debugPrint('Calendar export failed: $e');
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not open the calendar file on this device.'),
      ),
    );
  }
}
