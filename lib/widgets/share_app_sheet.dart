import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'common.dart';
import '../services/analytics.dart';

/// Install page that the booth QR code points to.
const kGetAppUrl = 'https://kubecon.codemagic.app/get/';

/// App bar button that opens [ShareAppSheet].
class ShareAppAction extends StatelessWidget {
  const ShareAppAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Share the app',
    icon: const Icon(Icons.qr_code_2),
    onPressed: () => ShareAppSheet.show(context),
  );
}

/// A big QR code someone can scan straight off this phone, plus copy/share.
class ShareAppSheet extends StatelessWidget {
  const ShareAppSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const ShareAppSheet(),
  );

  Future<void> _share(BuildContext context) async {
    track(Events.shareApp);
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'KubeCon Companion: schedule, venue map with directions and reminders. Built with Codemagic. $kGetAppUrl',
          subject: 'KubeCon Companion',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      // No share sheet available (e.g. some desktop browsers): fall back to copying.
      if (context.mounted) await _copy(context);
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: kGetAppUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Link copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final qrSize = (MediaQuery.sizeOf(context).width - 96).clamp(180.0, 300.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share KubeCon Companion', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Scan to get the app on Android, iPhone or the web.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.asset(
                'assets/brand/qr-get.png',
                width: qrSize,
                height: qrSize,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'QR code for $kGetAppUrl',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText('kubecon.codemagic.app/get', style: text.bodyMedium),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SubtleButton(
                    icon: Icons.link,
                    label: 'Copy link',
                    onPressed: () => _copy(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Builder(
                    builder: (btnContext) => PrimaryButton(
                      icon: Icons.ios_share,
                      label: 'Share',
                      onPressed: () => _share(btnContext),
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
