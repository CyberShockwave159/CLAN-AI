import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:clan_ai/core/utils/browser_download.dart';

/// Platform-independent file saver.
///
/// On Android/iOS it delegates to native save dialogs via platform channels
/// (SAF on Android, UIDocumentPicker on iOS).
///
/// On desktop platforms (Linux, macOS, Windows) it writes directly to the
/// app's documents directory since those platforms do not sandbox file access.
///
/// On web it triggers a browser download (Blob URL + anchor click).
class FileSaver {
  static const MethodChannel _channel =
      MethodChannel('com.clanai.clan_ai/file_saver');

  /// Prompts the user to choose a save location and writes [content] there.
  ///
  /// [filename] is the suggested filename (sanitized by callers).
  /// [mimeType] should be [text/plain] or [application/json].
  ///
  /// Returns the final file path on success (the suggested filename on web,
  /// where browsers don't expose the destination), or `null` on failure.
  static Future<String?> saveFile({
    required String filename,
    required String content,
    required String mimeType,
  }) {
    if (kIsWeb) {
      return browserDownload(
        filename: filename,
        content: content,
        mimeType: mimeType,
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final contentBytes = Uint8List.fromList(utf8.encode(content));
      final base64Content = base64Encode(contentBytes);
      return _channel.invokeMethod<String>('saveFile', {
        'filename': filename,
        'content': base64Content,
        'mimeType': mimeType,
      });
    }

    // Desktop fallback: write to app documents directory
    return _saveToDocuments(filename: filename, content: content);
  }

  /// Saves arbitrary binary [bytes] (e.g. a downloaded artifact file) through
  /// the same platform paths as [saveFile]. Returns the final file path on
  /// success (the suggested filename on web), or `null` on failure.
  static Future<String?> saveBytes({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) {
    if (kIsWeb) {
      return browserDownload(
        filename: filename,
        content: '',
        bytes: bytes,
        mimeType: mimeType,
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final base64Content = base64Encode(bytes);
      return _channel.invokeMethod<String>('saveFile', {
        'filename': filename,
        'content': base64Content,
        'mimeType': mimeType,
      });
    }

    // Desktop fallback: write to app documents directory
    return _saveBytesToDocuments(filename: filename, bytes: bytes);
  }

  static Future<String> _saveBytesToDocuments({
    required String filename,
    required Uint8List bytes,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
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