import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../data/live_data.dart';

LiveDataSource? createLiveDataSource() => WebLiveDataSource();

/// `fetch` with `cache: no-store`. Nothing is cached here: the service
/// worker keeps the offline copy and serves it when the network is down.
class WebLiveDataSource implements LiveDataSource {
  @override
  Future<String> fetch(String name) async {
    // The service worker would answer from its cache while offline; report
    // offline instead so the user is told.
    if (!web.window.navigator.onLine) throw StateError('offline');
    final res = await web.window
        .fetch(_url(name).toJS, web.RequestInit(cache: 'no-store'))
        .toDart
        .timeout(liveDataTimeout);
    if (res.status != 200) throw StateError('HTTP ${res.status} for $name');
    return (await res.text().toDart).toDart;
  }

  /// Same origin as the page (the live site, or a preview / localhost
  /// build), so there is no CORS to worry about.
  static String _url(String name) {
    try {
      return Uri.parse(web.document.baseURI)
          .resolve('assets/assets/data/$name')
          .toString();
    } catch (_) {
      return '$liveDataBaseUrl$name';
    }
  }

  @override
  Future<CachedData?> readCache(String name) async => null;

  @override
  Future<void> writeCache(String name, String body, {int? bundledHash}) async {}
}
