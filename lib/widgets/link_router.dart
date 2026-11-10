import 'dart:async';

import 'package:flutter/material.dart';

import '../data/agenda_link.dart';
import '../data/spot_link.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
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

/// What a link that opened the app asks for.
sealed class AppLink {
  const AppLink();

  /// Reads [uri]; null for links the app has nothing to do with. Never
  /// throws.
  static AppLink? parse(Uri uri) {
    final agenda = agendaFromLink(uri);
    if (agenda != null) return AgendaAppLink(agenda);
    final spot = spotParamFrom(uri);
    if (spot != null) return SpotAppLink(spot);
    return null;
  }

  /// Identity for ignoring the same link reported twice.
  String get key;
}

/// `?agenda=a1.…`: offer to import a shared agenda.
class AgendaAppLink extends AppLink {
  const AgendaAppLink(this.payload);
  final String payload;
  @override
  String get key => 'agenda:$payload';
}

/// `?at=v1.…`: show a shared spot on the Map tab.
class SpotAppLink extends AppLink {
  const SpotAppLink(this.payload);
  final String payload;
  @override
  String get key => 'at:$payload';
}

/// Pins a shared spot from [payload], or says the link is broken.
void openSpotLink(BuildContext context, AppState app, String payload) {
  final spot = decodeSpot(payload);
  if (spot == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('That spot link is not valid.')),
    );
    return;
  }
  app.showSpot(spot);
}

/// Handles links that open the native app ([links]): shared agendas offer
/// an import, shared spots open on the Map tab; other links are ignored.
class LinkRouter extends StatefulWidget {
  const LinkRouter({super.key, required this.links, required this.child});

  final Stream<Uri> links;
  final Widget child;

  @override
  State<LinkRouter> createState() => _LinkRouterState();
}

class _LinkRouterState extends State<LinkRouter> {
  StreamSubscription<Uri>? _sub;
  bool _busy = false;
  String? _last;
  final _sinceLast = Stopwatch();

  @override
  void initState() {
    super.initState();
    _sub = widget.links.listen(
      _onLink,
      // A platform without the plugin, or a bad link: nothing to do.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onLink(Uri uri) async {
    final link = AppLink.parse(uri);
    if (link == null || _busy) return;
    // The same link can be reported twice around a cold start.
    if (link.key == _last && _sinceLast.elapsed < const Duration(seconds: 5)) {
      return;
    }
    _last = link.key;
    _sinceLast
      ..reset()
      ..start();
    _busy = true;
    try {
      // Links can arrive before the first frame on a cold start.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final app = AppScope.read(context);
      switch (link) {
        case AgendaAppLink(:final payload):
          await confirmAgendaImport(context, app, payload);
        case SpotAppLink(:final payload):
          openSpotLink(context, app, payload);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
