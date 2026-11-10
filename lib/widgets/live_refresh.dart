import 'package:flutter/material.dart';

import '../data/venue_time.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../services/analytics.dart';

/// Snack text for a finished refresh.
String refreshMessage(RefreshResult r) =>
    r.offline ? 'Offline — showing saved schedule' : 'Updated ${fmtTime(r.at)}';

/// Pull-to-refresh: fetches the latest data ([AppState.refresh]) and says
/// how it went. Wrap a tab body; any vertical list inside works, and short
/// or non-scrolling content can still be pulled.
class LiveRefresh extends StatefulWidget {
  const LiveRefresh({super.key, required this.child});

  final Widget child;

  @override
  State<LiveRefresh> createState() => _LiveRefreshState();
}

class _LiveRefreshState extends State<LiveRefresh> {
  ScrollBehavior? _parent;
  late ScrollBehavior _behavior;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lists shorter than the screen must still be pullable. Built only when
    // the inherited behavior changes: a new behavior on every build would
    // make every list below rebuild its scroll position.
    final parent = ScrollConfiguration.of(context);
    if (!identical(parent, _parent)) {
      _parent = parent;
      _behavior = parent.copyWith(
        physics: AlwaysScrollableScrollPhysics(
          parent: parent.getScrollPhysics(context),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    track(Events.refresh);
    final app = AppScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await app.refresh();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(refreshMessage(result))));
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    // Lists can sit inside a TabBarView (another scrollable): accept any
    // vertical list, not only a direct child.
    notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
    child: ScrollConfiguration(behavior: _behavior, child: widget.child),
  );
}

/// [child] (e.g. an [EmptyState]) in a scroll view filling the space, so a
/// [LiveRefresh] around it can be pulled.
class PullableFill extends StatelessWidget {
  const PullableFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}
