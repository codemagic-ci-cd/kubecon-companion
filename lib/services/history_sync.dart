import 'dart:async';

import 'package:flutter/material.dart';

import 'history_api_io.dart'
    if (dart.library.js_interop) 'history_api_web.dart'
    as impl;

/// The browser's history, reduced to what [HistorySync] needs. Each entry
/// carries the page depth it was created for.
abstract class HistoryApi {
  /// Depth stored in the current entry, or null when it isn't ours.
  int? get depth;

  void replace(int depth);
  void push(int depth);
  void go(int delta);

  /// Depths of entries the user moves to with back/forward (or a swipe).
  Stream<int?> get pops;
}

/// The real browser history on the web; null in the native apps.
HistoryApi? browserHistory() => impl.browserHistory();

/// Keeps browser back/forward in step with pages pushed on the app's root
/// navigator: every page gets its own history entry, back closes it and
/// forward opens it again.
///
/// Only full pages ([MaterialPageRoute]) get entries; sheets and dialogs on
/// top are closed first when going back.
class HistorySync extends NavigatorObserver {
  HistorySync(this.api) {
    api.replace(0);
    _sub = api.pops.listen(_onPop);
  }

  final HistoryApi api;
  late final StreamSubscription<int?> _sub;

  /// Page depth the browser history is at (0 = home).
  int _depth = 0;

  /// Pages closed in the app or by going back, newest last, for forward.
  final _forward = <MaterialPageRoute<dynamic>>[];

  /// Set while we pop or push routes because of a browser navigation, so
  /// those changes don't write history again.
  bool _fromBrowser = false;

  /// In-app pops not yet mirrored to the browser (sent in one go).
  int _pendingBack = 0;

  /// Browser pop events caused by our own [HistoryApi.go] calls.
  int _ignorePops = 0;

  void dispose() => _sub.cancel();

  static bool _isPage(Route<dynamic> r) => r is MaterialPageRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route) || previousRoute == null) return; // home is depth 0
    _depth++;
    if (_fromBrowser) return;
    _flushBack();
    _forward.clear();
    api.push(_depth);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _closed(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _closed(route);

  void _closed(Route<dynamic> route) {
    if (!_isPage(route) || _depth == 0) return;
    _depth--;
    _forward.add(route as MaterialPageRoute<dynamic>);
    if (_fromBrowser) return;
    // Several pops in one go (popUntil) become a single history move.
    if (_pendingBack++ == 0) scheduleMicrotask(_flushBack);
  }

  void _flushBack() {
    if (_pendingBack == 0) return;
    final n = _pendingBack;
    _pendingBack = 0;
    _ignorePops++;
    api.go(-n);
  }

  void _onPop(int? target) {
    if (_ignorePops > 0) {
      _ignorePops--;
      return;
    }
    final nav = navigator;
    if (nav == null) return;
    final want = target ?? 0;
    _fromBrowser = true;
    try {
      // Back: close the top route until we're at the wanted page depth
      // (sheets and dialogs on top close first).
      while (_depth > want && nav.canPop()) {
        nav.pop();
      }
      // Forward: open the pages closed most recently, in order.
      while (_depth < want && _forward.isNotEmpty) {
        final old = _forward.removeLast();
        nav.push(
          MaterialPageRoute<dynamic>(
            builder: old.builder,
            settings: old.settings,
          ),
        );
      }
    } finally {
      _fromBrowser = false;
    }
    // History has entries we can't rebuild (e.g. after a reload): keep the
    // browser in step with what's on screen.
    if (_depth != want) api.replace(_depth);
  }
}
