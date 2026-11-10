import 'dart:convert';

import 'models.dart' show parseInstant;

/// Data files that pull-to-refresh fetches from the live site.
const liveDataFiles = [
  'schedule.json',
  'details.json',
  'sponsors.json',
  'happenings.json',
];

/// Where the published web app serves its bundled data.
const liveDataBaseUrl = 'https://kubecon.codemagic.app/assets/assets/data/';

/// Network timeout for one data file.
const liveDataTimeout = Duration(seconds: 10);

/// Pull-to-refresh is automatic on resume when the last one is older.
const autoRefreshAfter = Duration(minutes: 30);

/// A data file saved after a successful refresh.
class CachedData {
  const CachedData({required this.body, this.bundledHash});

  final String body;

  /// [fingerprint] of the bundled copy when this was saved; tells whether
  /// the app (and its bundled data) was updated since.
  final int? bundledHash;
}

/// Fetches live data files and keeps the last good copy of each.
abstract class LiveDataSource {
  /// The body of [name] from the live site; throws when offline, on a
  /// timeout or a non-200 response.
  Future<String> fetch(String name);

  /// The saved copy of [name], or null.
  Future<CachedData?> readCache(String name);

  /// Saves [body] as the copy of [name]; best effort.
  Future<void> writeCache(String name, String body, {int? bundledHash});
}

/// Top-level `fetchedAt` (or `version`) of a data file; null without one.
DateTime? dataVersion(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    return parseInstant(j['fetchedAt']) ?? parseInstant(j['version']);
  } catch (_) {
    return null;
  }
}

/// A stable 32-bit FNV-1a hash of [s] (String.hashCode is not stable across
/// runs or platforms).
int fingerprint(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Whether a saved copy should be used instead of the bundled one at start.
///
/// When both carry a version, the newer wins. Without versions (e.g.
/// happenings.json), the saved copy wins only while the bundled data is the
/// same as when it was saved: an app update brings fresh bundled data.
bool preferCached(CachedData cached, String bundled) {
  final vc = dataVersion(cached.body), vb = dataVersion(bundled);
  if (vc != null && vb != null) return vc.isAfter(vb);
  final h = cached.bundledHash;
  return h != null && h == fingerprint(bundled);
}

/// Whether freshly fetched data may replace what is loaded: not when both
/// have versions and the fetched one is older.
bool fetchedIsCurrent(String fetched, DateTime? loadedVersion) {
  final vf = dataVersion(fetched);
  if (vf == null || loadedVersion == null) return true;
  return !vf.isBefore(loadedVersion);
}

/// Parses the saved copy of [name] when [preferCached] says so and it
/// parses, else the bundled copy. Null when neither can be read. Never
/// touches the network.
Future<({T value, String raw, bool fromCache})?> loadPreferred<T>(
  String name, {
  required Future<String> Function() bundled,
  required T Function(String raw) parse,
  LiveDataSource? live,
}) async {
  String? b;
  try {
    b = await bundled();
  } catch (_) {
    b = null;
  }
  CachedData? c;
  if (live != null) {
    try {
      c = await live.readCache(name);
    } catch (_) {
      c = null;
    }
  }
  if (c != null && (b == null || preferCached(c, b))) {
    try {
      return (value: parse(c.body), raw: c.body, fromCache: true);
    } catch (_) {
      // A broken saved copy: fall back to the bundled one.
    }
  }
  if (b == null) return null;
  try {
    return (value: parse(b), raw: b, fromCache: false);
  } catch (_) {
    return null;
  }
}
