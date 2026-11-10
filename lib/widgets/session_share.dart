import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/session_link.dart';
import '../data/venue_time.dart';
import '../services/analytics.dart';
import 'agenda_share.dart' show CopyLinkButton, LinkQr;
import 'common.dart';

/// A QR code and link to one session, so someone else can open it in the
/// app or on the web.
class SessionShareSheet extends StatelessWidget {
  const SessionShareSheet({super.key, required this.session, this.place});

  final Session session;

  /// Room or venue label, for the share text.
  final String? place;

  static Future<void> show(
    BuildContext context,
    Session session, {
    String? place,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SessionShareSheet(session: session, place: place),
  );

  String get _when =>
      '${fmtDayShort(venueDay(session.start))} · ${fmtTime(session.start)}';

  Future<void> _share(BuildContext context, String link) async {
    track(Events.shareSession, {'session': session.title});
    final box = context.findRenderObject() as RenderBox?;
    final where = place == null ? '' : ', $place';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${session.title} ($_when$where) at KubeCon: $link',
          subject: session.title,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final ok = await _copy(link);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Link copied' : "Sharing isn't available on this device",
          ),
        ),
      );
    }
  }

  Future<bool> _copy(String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final link = sessionLink(session.id);
    final qrSize = (MediaQuery.sizeOf(context).width - 96).clamp(180.0, 300.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share session', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              session.title,
              style: text.titleSmall,
              textAlign: TextAlign.center,
            ),
            Text(
              place == null ? _when : '$_when · $place',
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            LinkQr(
              key: const ValueKey('session-qr'),
              data: link,
              size: qrSize,
              label: 'QR code for this session',
            ),
            const SizedBox(height: 12),
            SelectableText(
              link,
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: CopyLinkButton(onCopy: () => _copy(link))),
                const SizedBox(width: 12),
                Expanded(
                  child: Builder(
                    builder: (btnContext) => PrimaryButton(
                      icon: Icons.ios_share,
                      label: 'Share',
                      onPressed: () => _share(btnContext, link),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
