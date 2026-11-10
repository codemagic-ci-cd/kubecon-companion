import '../data/live_data.dart';
import 'live_data_source_io.dart'
    if (dart.library.js_interop) 'live_data_source_web.dart'
    as impl;

/// The platform's [LiveDataSource]: HTTP + an on-disk cache on native, a
/// `cache: no-store` fetch on the web (where the service worker keeps the
/// offline copy). Null where live data is not supported.
LiveDataSource? createLiveDataSource() => impl.createLiveDataSource();
