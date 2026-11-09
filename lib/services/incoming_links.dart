import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Links that opened the native app (Android App Links, iOS Universal
/// Links): the launch link first, then any while it runs.
///
/// Null on web, where `main` reads the launch URL from `Uri.base` instead.
Stream<Uri>? incomingLinks() {
  if (kIsWeb) return null;
  try {
    return AppLinks().uriLinkStream;
  } catch (_) {
    return null;
  }
}
