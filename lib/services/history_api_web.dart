import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'history_sync.dart';

HistoryApi? browserHistory() => _BrowserHistory();

class _BrowserHistory implements HistoryApi {
  _BrowserHistory() {
    web.window.addEventListener(
      'popstate',
      ((web.PopStateEvent e) => _pops.add(_depthOf(e.state))).toJS,
    );
  }

  final _pops = StreamController<int?>.broadcast();

  static int? _depthOf(JSAny? state) {
    final d = (state?.dartify() as Map?)?['kc'];
    return d is num ? d.toInt() : null;
  }

  JSAny _state(int depth) => {'kc': depth}.jsify()!;

  @override
  int? get depth => _depthOf(web.window.history.state);

  @override
  void replace(int depth) => web.window.history.replaceState(
    _state(depth),
    '',
    web.window.location.href,
  );

  @override
  void push(int depth) =>
      web.window.history.pushState(_state(depth), '', web.window.location.href);

  @override
  void go(int delta) => web.window.history.go(delta);

  @override
  Stream<int?> get pops => _pops.stream;
}
