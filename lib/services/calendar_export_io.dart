import 'dart:io';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

Future<void> deliverIcs({
  required String filename,
  required String content,
  Rect? origin,
}) async {
  final dir = await Directory.systemTemp.createTemp('kubecon-ics');
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content, flush: true);
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/calendar', name: filename)],
      subject: filename,
      sharePositionOrigin: origin,
    ),
  );
  if (result.status == ShareResultStatus.unavailable) {
    throw StateError('Sharing unavailable');
  }
}
