import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [content] (or the raw [bytes] when provided)
/// as a file named [filename].
///
/// Uses a Blob URL + programmatic anchor click (the standard PWA approach).
/// Returns the suggested [filename] so callers can report what was saved;
/// browsers don't expose the final destination path.
Future<String?> browserDownload({
  required String filename,
  required String content,
  required String mimeType,
  List<int>? bytes,
}) async {
  final parts = <JSAny>[
    if (bytes != null)
      Uint8List.fromList(bytes).toJS
    else
      utf8.encode(content).toJS,
  ].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  try {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    web.URL.revokeObjectURL(url);
  }
  return filename;
}