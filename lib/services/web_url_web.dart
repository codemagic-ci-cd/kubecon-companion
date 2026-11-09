import 'package:web/web.dart' as web;

void removeQueryParam(String name) {
  try {
    final uri = Uri.parse(web.window.location.href);
    if (!uri.queryParameters.containsKey(name)) return;
    final params = Map.of(uri.queryParametersAll)..remove(name);
    final query = params.isEmpty
        ? ''
        : '?${Uri(queryParameters: params).query}';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    // Keep Flutter's history state so its navigation keeps working.
    web.window.history.replaceState(
      web.window.history.state,
      '',
      '${uri.path}$query$fragment',
    );
  } catch (_) {
    // Best effort: the param stays in the address bar.
  }
}
