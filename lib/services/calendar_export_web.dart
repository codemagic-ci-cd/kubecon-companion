import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

Future<void> deliverIcs({
  required String filename,
  required String content,
  Rect? origin,
}) async {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/calendar;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Give the browser time to start the download before releasing the blob.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
