import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Platform-independent file saver.
///
/// On Android/iOS it delegates to native save dialogs via platform channels
/// (SAF on Android, UIDocumentPicker on iOS).
///
/// On desktop platforms (Linux, macOS, Windows) it writes directly to the
/// app's documents directory since those platforms do not sandbox file access.
class FileSaver {
  static const MethodChannel _channel =
      MethodChannel('com.clanai.clan_ai/file_saver');

  /// Prompts the user to choose a save location and writes [content] there.
  ///
  /// [filename] is the suggested filename (sanitized by callers).
  /// [mimeType] should be [text/plain] or [application/json].
  ///
  /// Returns the final file path on success, or `null` if cancelled / failed.
  static Future<String?> saveFile({
    required String filename,
    required String content,
    required String mimeType,
  }) {
    if (Platform.isAndroid || Platform.isIOS) {
      final contentBytes = Uint8List.fromList(utf8.encode(content));
      final base64Content = base64Encode(contentBytes);
      return _channel.invokeMethod<String>('saveFile', {
        'filename': filename,
        'content': base64Content,
        'mimeType': mimeType,
      });
    }

    // Desktop / web fallback: write to app documents directory
    return _saveToDocuments(filename: filename, content: content);
  }

  static Future<String> _saveToDocuments({
    required String filename,
    required String content,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    return file.path;
  }
}
