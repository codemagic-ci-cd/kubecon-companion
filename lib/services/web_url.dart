import 'web_url_io.dart'
    if (dart.library.js_interop) 'web_url_web.dart'
    as impl;

/// Removes query parameter [name] from the address bar without reloading
/// (web only; a no-op elsewhere).
void removeQueryParam(String name) => impl.removeQueryParam(name);
