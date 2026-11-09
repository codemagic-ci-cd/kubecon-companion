import 'dart:ui' show Rect;

import 'calendar_export_io.dart'
    if (dart.library.js_interop) 'calendar_export_web.dart'
    as impl;

/// Hands an .ics file to the platform: a download on the web (iOS Safari
/// opens it in Calendar), the share sheet on Android/iOS so the user can
/// pick their calendar app. Throws when that is not possible.
typedef IcsDeliverer = Future<void> Function({
  required String filename,
  required String content,
  Rect? origin,
});

/// Replaced in tests.
IcsDeliverer deliverIcs = impl.deliverIcs;
