import 'agenda_link.dart' show kAppBaseUrl;

/// Query parameter the web app reads to open a session.
const kSessionParam = 'session';

final _sharePath = RegExp(r'^/s/([A-Za-z0-9_-]+)(\.html)?$');

/// `https://kubecon.codemagic.app/s/ID.html`: a static page with the
/// session's own link preview (title, time, room, speakers) that forwards to
/// the web app; the native apps open it directly via universal / app links.
/// Pages are made by tool/build_share_pages.py.
String sessionLink(String id) => '${kAppBaseUrl}s/$id.html';

/// The session id in [uri] (`/s/ID.html` or `?session=ID`), or null.
/// Never throws.
String? sessionParamFrom(Uri? uri) {
  if (uri == null) return null;
  try {
    final m = _sharePath.firstMatch(uri.path);
    if (m != null) return m.group(1);
    final v = uri.queryParameters[kSessionParam];
    return v == null || v.isEmpty ? null : v;
  } catch (_) {
    return null;
  }
}
