import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/agenda_link.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'common.dart';

/// A QR code and link that carry the user's saved sessions, so someone else
/// can import them. No backend: everything is in the link.
class AgendaShareSheet extends StatelessWidget {
  const AgendaShareSheet({super.key, required this.ids});

  final Iterable<String> ids;

  static Future<void> show(BuildContext context, Iterable<String> ids) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AgendaShareSheet(ids: ids),
      );

  Future<void> _share(BuildContext context, String link, int count) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'My KubeCon agenda ($count ${count == 1 ? 'session' : 'sessions'}). Open to add them to your KubeCon Companion: $link',
          subject: 'My KubeCon agenda',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      // No share sheet (e.g. some desktop browsers): copy instead, and close
      // the sheet so the snackbar is visible.
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final ok = await _copy(context, link);
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

  /// False when the browser refused clipboard access.
  Future<bool> _copy(BuildContext context, String link) async {
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
    final count = ids.toSet().length;
    final link = agendaLink(ids);
    final qrSize = (MediaQuery.sizeOf(context).width - 96).clamp(180.0, 300.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share my agenda', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Scan or open the link to add your $count saved ${count == 1 ? 'session' : 'sessions'} to KubeCon Companion.',
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
              child: Semantics(
                label: 'QR code for your agenda link',
                child: QrImageView(
                  key: const ValueKey('agenda-qr'),
                  data: link,
                  size: qrSize,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF01091A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF01091A),
                  ),
                ),
              ),
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
                Expanded(
                  child: _CopyLinkButton(onCopy: () => _copy(context, link)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Builder(
                    builder: (btnContext) => PrimaryButton(
                      icon: Icons.ios_share,
                      label: 'Share',
                      onPressed: () => _share(btnContext, link, count),
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

/// "Copy link" that briefly turns into "Copied". A snackbar would be hidden
/// behind the modal sheet.
class _CopyLinkButton extends StatefulWidget {
  const _CopyLinkButton({required this.onCopy});

  final Future<bool> Function() onCopy;

  @override
  State<_CopyLinkButton> createState() => _CopyLinkButtonState();
}

class _CopyLinkButtonState extends State<_CopyLinkButton> {
  Timer? _reset;
  bool? _copied;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _onPressed() async {
    final ok = await widget.onCopy();
    if (!mounted) return;
    setState(() => _copied = ok);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) => SubtleButton(
    icon: switch (_copied) {
      true => Icons.check,
      false => Icons.error_outline,
      null => Icons.link,
    },
    label: switch (_copied) {
      true => 'Copied',
      false => "Couldn't copy",
      null => 'Copy link',
    },
    onPressed: _onPressed,
  );
}

/// Asks before adding the sessions in [payload] to saved, then reports what
/// happened in a snackbar. Returns how many sessions were added.
Future<int> confirmAgendaImport(
  BuildContext context,
  AppState app,
  String payload,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  final ids = decodeAgenda(payload);
  if (ids == null) {
    say('That agenda link is not valid.');
    return 0;
  }
  final known = ids.where((id) => app.data.session(id) != null).toList();
  if (known.isEmpty) {
    say('No sessions from that agenda are on the current schedule.');
    return 0;
  }
  final fresh = app.importableSessions(known);
  if (fresh.isEmpty) {
    say('You already have every session from that agenda saved.');
    return 0;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AgendaImportDialog(
      sessions: fresh,
      alreadySaved: known.length - fresh.length,
    ),
  );
  if (ok != true) return 0;
  final added = await app.importSaved(fresh.map((s) => s.id));
  say('Added $added ${added == 1 ? 'session' : 'sessions'} to Saved.');
  return added;
}

/// "Import N sessions from a shared agenda?" with the first few titles.
class AgendaImportDialog extends StatelessWidget {
  const AgendaImportDialog({
    super.key,
    required this.sessions,
    this.alreadySaved = 0,
  });

  final List<Session> sessions;
  final int alreadySaved;

  static const _preview = 4;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = sessions.length;
    final more = n - _preview;
    return AlertDialog(
      title: Text(
        'Import $n ${n == 1 ? 'session' : 'sessions'} from a shared agenda?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in sessions.take(_preview))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.star_outline_rounded, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.title, style: text.bodyMedium)),
                  ],
                ),
              ),
            if (more > 0) Text('and $more more', style: text.bodySmall),
            const SizedBox(height: 8),
            Text(
              [
                'They are added to Saved with a reminder 10 minutes before each starts. Nothing you saved is removed.',
                if (alreadySaved > 0) '$alreadySaved already in your Saved.',
              ].join(' '),
              style: text.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

/// Paste field for an agenda link (native apps cannot be opened by the link).
/// Pops with the payload, or null.
class PasteAgendaDialog extends StatefulWidget {
  const PasteAgendaDialog({super.key});

  @override
  State<PasteAgendaDialog> createState() => _PasteAgendaDialogState();
}

class _PasteAgendaDialogState extends State<PasteAgendaDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t != null && mounted) {
      setState(() {
        _controller.text = t.trim();
        _error = null;
      });
    }
  }

  void _submit() {
    final payload = agendaPayloadFrom(_controller.text);
    if (payload == null || decodeAgenda(payload) == null) {
      setState(() => _error = 'That does not look like an agenda link.');
      return;
    }
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import agenda link'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste a link someone shared from "Share my agenda".',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('agenda-link-field'),
          controller: _controller,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'kubecon.codemagic.app/?agenda=…',
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste),
              onPressed: _paste,
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Continue')),
    ],
  );
}
