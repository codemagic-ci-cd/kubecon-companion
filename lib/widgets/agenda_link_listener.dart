import 'dart:async';

import 'package:flutter/material.dart';

import '../data/agenda_link.dart';
import '../state/app_scope.dart';
import 'agenda_share.dart';

/// The agenda payload of an opened link, or null when it carries none.
/// Never throws.
String? agendaFromLink(Uri uri) {
  try {
    final v = uri.queryParameters[kAgendaParam];
    return v == null || v.isEmpty ? null : v;
  } catch (_) {
    // Malformed percent-encoding in the query.
    return null;
  }
}

/// Offers to import the agenda of every shared agenda link that opens the
/// native app ([links]); other links are ignored.
class AgendaLinkListener extends StatefulWidget {
  const AgendaLinkListener({
    super.key,
    required this.links,
    required this.child,
  });

  final Stream<Uri> links;
  final Widget child;

  @override
  State<AgendaLinkListener> createState() => _AgendaLinkListenerState();
}

class _AgendaLinkListenerState extends State<AgendaLinkListener> {
  StreamSubscription<Uri>? _sub;
  bool _busy = false;
  String? _last;
  final _sinceLast = Stopwatch();

  @override
  void initState() {
    super.initState();
    _sub = widget.links.listen(
      _onLink,
      // A platform without the plugin, or a bad link: nothing to offer.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onLink(Uri uri) async {
    final payload = agendaFromLink(uri);
    if (payload == null || _busy) return;
    // The same link can be reported twice around a cold start.
    if (payload == _last && _sinceLast.elapsed < const Duration(seconds: 5)) {
      return;
    }
    _last = payload;
    _sinceLast
      ..reset()
      ..start();
    _busy = true;
    try {
      // Links can arrive before the first frame on a cold start.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await confirmAgendaImport(context, AppScope.read(context), payload);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
