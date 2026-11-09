import 'dart:convert';

import 'package:flutter/services.dart';

import 'outdoor_map.dart';

const outdoorAsset = 'assets/data/outdoor.json';

typedef OutdoorLoader = Future<OutdoorMap?> Function(AssetBundle bundle);

Future<OutdoorMap?>? _cache;

/// Loads the outdoor map on first use (only when off-site directions open)
/// and keeps it in memory. Resolves to null when the asset is missing or
/// broken; a failed load is retried next time.
Future<OutdoorMap?> loadOutdoorMap(AssetBundle bundle) {
  final cached = _cache;
  if (cached != null) return cached;
  final f = _load(bundle);
  _cache = f;
  f.then((m) {
    if (m == null && identical(_cache, f)) _cache = null;
  });
  return f;
}

Future<OutdoorMap?> _load(AssetBundle bundle) async {
  try {
    final raw = await bundle.loadString(outdoorAsset, cache: false);
    return OutdoorMap.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}
