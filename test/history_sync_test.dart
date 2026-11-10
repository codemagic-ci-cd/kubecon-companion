import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/services/history_sync.dart';

/// Behaves like window.history: a list of entries and a position; push drops
/// forward entries; go() fires a popstate asynchronously.
class FakeHistory implements HistoryApi {
  final entries = <int>[0];
  int index = 0;
  final _pops = StreamController<int?>.broadcast(sync: false);

  @override
  int? get depth => entries[index];
  @override
  void replace(int depth) => entries[index] = depth;
  @override
  void push(int depth) {
    entries
      ..removeRange(index + 1, entries.length)
      ..add(depth);
    index++;
  }

  @override
  void go(int delta) {
    final to = (index + delta).clamp(0, entries.length - 1);
    if (to == index) return;
    index = to;
    scheduleMicrotask(() => _pops.add(entries[index]));
  }

  /// The user pressing the browser's back/forward (or swiping).
  void back() => go(-1);
  void forward() => go(1);

  @override
  Stream<int?> get pops => _pops.stream;
}

Widget _page(String name) => Scaffold(
  appBar: AppBar(title: Text(name)),
  body: Builder(
    builder: (context) => TextButton(
      onPressed: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => _page('$name+'))),
      child: Text('open from $name'),
    ),
  ),
);

void main() {
  testWidgets('browser back and forward follow pushed pages', (tester) async {
    final history = FakeHistory();
    final sync = HistorySync(history);
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [sync], home: _page('home')),
    );

    await tester.tap(find.text('open from home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open from home+'));
    await tester.pumpAndSettle();
    expect(find.text('home++'), findsOneWidget);
    expect(history.entries, [0, 1, 2]);

    history.back();
    await tester.pumpAndSettle();
    expect(find.text('home+'), findsOneWidget);
    expect(find.text('home++'), findsNothing);

    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('home++'), findsOneWidget);

    history.back();
    await tester.pumpAndSettle();
    history.back();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('home+'), findsNothing);

    history.forward();
    await tester.pumpAndSettle();
    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('home++'), findsOneWidget);
  });

  testWidgets('the in-app back button moves browser history too', (
    tester,
  ) async {
    final history = FakeHistory();
    final sync = HistorySync(history);
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [sync], home: _page('home')),
    );
    await tester.tap(find.text('open from home'));
    await tester.pumpAndSettle();
    expect(history.index, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(history.index, 0); // browser went back with it

    // ...and browser forward reopens the page.
    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('home+'), findsOneWidget);

    // Opening a new page from home drops the old forward entry.
    history.back();
    await tester.pumpAndSettle();
    await tester.tap(find.text('open from home'));
    await tester.pumpAndSettle();
    expect(history.entries, [0, 1]);
    expect(history.index, 1);
  });

  testWidgets('popUntil to home is one browser move', (tester) async {
    final history = FakeHistory();
    final sync = HistorySync(history);
    addTearDown(sync.dispose);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [sync],
        home: _page('home'),
      ),
    );
    await tester.tap(find.text('open from home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open from home+'));
    await tester.pumpAndSettle();
    key.currentState!.popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(history.index, 0);
  });

  testWidgets('back closes a sheet before the page under it', (tester) async {
    final history = FakeHistory();
    final sync = HistorySync(history);
    addTearDown(sync.dispose);
    await tester.pumpWidget(
      MaterialApp(navigatorObservers: [sync], home: _page('home')),
    );
    await tester.tap(find.text('open from home'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('home+'));
    unawaited(
      showModalBottomSheet<void>(
        context: ctx,
        builder: (_) => const Text('sheet'),
      ),
    );
    await tester.pumpAndSettle();
    history.back();
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
