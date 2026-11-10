import 'agenda_link.dart' show kAppBaseUrl;

/// Query parameter of a shared session link.
const kSessionParam = 'session';

/// `https://kubecon.codemagic.app/?session=ID` opens that session's page in
/// the web app, or in the native app via universal / app links.
String sessionLink(String id) =>
    '$kAppBaseUrl?$kSessionParam=${Uri.encodeQueryComponent(id)}';

/// The session id in [uri], or null. Never throws.
String? sessionParamFrom(Uri? uri) {
  try {
    final v = uri?.queryParameters[kSessionParam];
    return v == null || v.isEmpty ? null : v;
  } catch (_) {
    return null;
  }
}
