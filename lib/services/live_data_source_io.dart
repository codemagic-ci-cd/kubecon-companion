import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/live_data.dart';

LiveDataSource? createLiveDataSource() => NativeLiveDataSource();

/// Fetches with `package:http` and keeps the last good copy of each file in
/// the app support directory (`live_data/<name>` + `<name>.meta.json`).
class NativeLiveDataSource implements LiveDataSource {
  NativeLiveDataSource({
    http.Client? client,
    Future<Directory> Function()? baseDir,
  }) : _client = client ?? http.Client(),
       _baseDir = baseDir ?? getApplicationSupportDirectory;

  final http.Client _client;
  final Future<Directory> Function() _baseDir;
  Future<Directory>? _dir;

  Future<Directory> _cacheDir() => _dir ??= () async {
    final d = Directory('${(await _baseDir()).path}/live_data');
    await d.create(recursive: true);
    return d;
  }();

  @override
  Future<String> fetch(String name) async {
    final res = await _client
        .get(
          Uri.parse('$liveDataBaseUrl$name'),
          headers: const {'Cache-Control': 'no-cache'},
        )
        .timeout(liveDataTimeout);
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} for $name');
    }
    return utf8.decode(res.bodyBytes);
  }

  @override
  Future<CachedData?> readCache(String name) async {
    try {
      final dir = await _cacheDir();
      final body = File('${dir.path}/$name');
      if (!await body.exists()) return null;
      int? hash;
      try {
        final meta = jsonDecode(
          await File('${dir.path}/$name.meta.json').readAsString(),
        );
        if (meta is Map && meta['bundledHash'] is int) {
          hash = meta['bundledHash'] as int;
        }
      } catch (_) {
        // No or broken meta: versions alone decide.
      }
      return CachedData(body: await body.readAsString(), bundledHash: hash);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeCache(String name, String body, {int? bundledHash}) async {
    try {
      final dir = await _cacheDir();
      // Write then rename, so a crash never leaves half a file.
      final tmp = File('${dir.path}/$name.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename('${dir.path}/$name');
      await File('${dir.path}/$name.meta.json').writeAsString(
        jsonEncode({
          'bundledHash': ?bundledHash,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Best effort: the next start uses the bundled data.
    }
  }
}
