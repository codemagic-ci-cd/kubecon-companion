import 'package:flutter/widgets.dart';

import '../services/analytics.dart';

/// Counts [event] once when this page opens (not on every rebuild).
class TrackView extends StatefulWidget {
  const TrackView({
    super.key,
    required this.event,
    this.props = const {},
    required this.child,
  });

  final String event;
  final Map<String, String> props;
  final Widget child;

  @override
  State<TrackView> createState() => _TrackViewState();
}

class _TrackViewState extends State<TrackView> {
  @override
  void initState() {
    super.initState();
    track(widget.event, widget.props);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
